# frozen_string_literal: true

RSpec.describe PublisherUser, truncate: true do
  let(:publisher_klass) { PubSubModelSync::MessagePublisher }
  let(:connector) { PubSubModelSync::MessagePublisher.connector }

  describe 'callbacks' do
    it '.create' do
      expect_publish_model([be_a(described_class), :create, any_args])
      mock_publisher_callback(%i[ps_after_action create], { name: 'name' }, :create!) do
        ps_publish(:create, mapping: %i[id name email])
      end
    end

    it '.update' do
      expect_publish_model([be_a(PublisherUser), :update, any_args])
      model = mock_publisher_callback(%i[ps_after_action update], { name: 'name' }, :create!) do
        ps_publish(:update, mapping: %i[id name email])
      end
      model.update!(name: 'changed name')
    end

    it '.destroy' do
      expect_publish_model([be_a(PublisherUser), :destroy, any_args])
      model = mock_publisher_callback(%i[ps_after_action destroy], { name: 'name' }, :create!) do
        ps_publish(:destroy, mapping: %i[id])
      end
      model.destroy!
    end

    it 'custom event' do
      expect_publish_model([be_a(PublisherUser), :custom, any_args])
      model = described_class.create!(name: 'sample')
      model.ps_publish(:custom, mapping: %i[id name])
    end
  end

  describe 'when performing notifications manually' do
    it 'calls the correct callback' do
      mock = -> {}
      model = mock_publisher_callback(%i[ps_after_action update], {}, :create!) { mock.call }
      expect(mock).to receive(:call)
      model.ps_perform_publish(:update)
    end

    it 'calls the correct method' do
      model = mock_publisher_callback(%i[ps_after_action update sync_update], {}, :create!)
      expect(model).to receive(:sync_update)
      model.ps_perform_publish(:update)
    end

    it 'uses parents callbacks if expected' do
      performed_callback = false
      model = mock_publisher_callback(%i[ps_after_action update sync_update], {}, :create!)
      callback_action = { actions: %i[update], callback: ->(_action) { performed_callback = true } }
      allow(model.class.superclass).to receive(:ps_cache_publish_callbacks).and_return([callback_action])
      model.ps_perform_publish(:update, parents_actions: true)
      expect(performed_callback).to be_truthy
    end
  end

  describe 'when ensuring notifications order' do
    let(:user_data) { { name: 'name', posts_attributes: [{ title: 'P1' }, { title: 'P2' }] } }
    let(:user) do
      mock_publisher_callback([:ps_after_action, %i[create update destroy]], user_data) do |action|
        ps_publish(action, mapping: %i[id name email])
      end
    end
    let(:key) { "PublisherUser/#{user.id}" }

    it 'publishes correct ordering-key when created' do
      calls = capture_notifications { user.save! }
      expect(calls[0]).to include({ klass: 'PublisherUser', action: :create, ordering_key: key, id: user.id })
      expect(calls[1]).to include({ klass: 'Post', action: :create, ordering_key: key, id: user.posts.first.id })
      expect(calls[2]).to include({ klass: 'Post', action: :create, ordering_key: key, id: user.posts.second.id })
    end

    it 'publishes correct ordering-key when updated' do
      user.save!
      changed_data = { name: 'Changed', posts_attributes: [{ id: user.posts.first.id, title: 'P1 changed' },
                                                           { id: user.posts.second.id, title: 'P2 changed' }] }
      calls = capture_notifications { user.update!(changed_data) }
      expect(calls[0]).to include({ klass: 'PublisherUser', action: :update, ordering_key: key, id: user.id })
      expect(calls[1]).to include({ klass: 'Post', action: :update, ordering_key: key, id: user.posts.first.id })
      expect(calls[2]).to include({ klass: 'Post', action: :update, ordering_key: key, id: user.posts.second.id })
    end

    it 'publishes correct ordering-key when destroyed (inverted)' do
      user.save!
      posts_ids = user.posts.pluck(:id)
      key = "Post/#{posts_ids.first}"
      calls = capture_notifications { user.destroy! }
      expect(calls[0]).to include({ klass: 'Post', action: :destroy, ordering_key: key, id: posts_ids.first })
      expect(calls[1]).to include({ klass: 'Post', action: :destroy, ordering_key: key, id: posts_ids.second })
      expect(calls[2]).to include({ klass: 'PublisherUser', action: :destroy, ordering_key: key, id: user.id })
    end
  end

  private

  # @return (PublisherUser)
  def capture_notifications(&block)
    calls = []
    allow(connector).to receive(:publish) do |payload|
      calls << payload.info.merge(payload.headers.slice(:ordering_key)).merge(id: payload.data[:id])
    end
    block.call
    calls
  end

  def expect_publish_model(args)
    expect(publisher_klass).to receive(:publish_model).with(*args)
  end

  describe '.ps_class_publish' do
    before { allow(publisher_klass).to receive(:publish_data) }

    it 'publishes a class notification' do
      described_class.ps_class_publish({ message: 'hello' }, action: :greeting)

      expect(publisher_klass)
        .to have_received(:publish_data).with('PublisherUser', { message: 'hello' }, :greeting, headers: {})
    end

    it 'publishes as another class when asked to' do
      described_class.ps_class_publish({}, action: :greeting, as_klass: :Visitor)

      expect(publisher_klass).to have_received(:publish_data).with('Visitor', {}, :greeting, headers: {})
    end
  end

  # The concern is not only for models: a plain class can publish class
  # notifications, it just has no transaction callbacks to hook into.
  describe 'when included in a class that is not a model' do
    let(:klass) do
      Class.new do
        include PubSubModelSync::PublisherConcern

        def self.name
          'Plain'
        end
      end
    end

    it 'publishes class notifications' do
      allow(publisher_klass).to receive(:publish_data)

      klass.ps_class_publish({}, action: :greeting)

      expect(publisher_klass).to have_received(:publish_data).with('Plain', {}, :greeting, headers: {})
    end
  end

  describe 'transaction callbacks' do
    let(:model) { described_class.new(name: 'name') }

    it 'ignores the commit of a transaction it did not start' do
      expect { model.run_callbacks(:commit) }.not_to raise_error
    end

    it 'ignores the rollback of a transaction it did not start' do
      expect { model.run_callbacks(:rollback) }.not_to raise_error
    end

    it 'rolls back the transaction it started' do
      transaction = instance_double(PubSubModelSync::Transaction, rollback: true)
      model.instance_variable_set(:@ps_transaction, transaction)

      model.run_callbacks(:rollback)

      expect(transaction).to have_received(:rollback)
    end
  end
end
