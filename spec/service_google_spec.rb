# frozen_string_literal: true

RSpec.describe PubSubModelSync::ServiceGoogle do
  let(:msg_attrs) { { 'service_model_sync' => true } }
  let(:payload_attrs) { { klass: 'Tester', action: :test } }
  let(:payload) { PubSubModelSync::Payload.new({}, payload_attrs) }
  let(:mock_message) do
    double('Message', data: payload.to_json, attributes: msg_attrs)
  end
  let(:mock_service_message) do
    double('ServiceMessage', message: mock_message, acknowledge!: true)
  end
  let(:mock_service_unknown_message) do
    mock_message.attributes['service_model_sync'] = nil
    mock_service_message
  end
  let(:inst) { described_class.new }
  let(:publisher) { inst.publishers.values.first }

  before do
    allow(inst).to receive(:sleep)
    allow(Process).to receive(:exit!)
  end

  describe 'initializer' do
    it 'connects to pub/sub service' do
      expect(inst.service).not_to be_nil
    end

    it 'connects to topic' do
      expect(publisher).not_to be_nil
    end

    it 'connects to multiple topics if provided' do
      names = ['topic 1', 'topic2']
      allow(described_class.config).to receive(:topic_name).and_return(names)

      expect(described_class.new.publishers.values.count).to eq names.count
    end

    it 'enables message ordering' do
      publisher_klass = PubSubModelSync::MockGoogleService::MockPublisher
      expect_any_instance_of(publisher_klass).to receive(:enable_message_ordering!)
      described_class.new
    end

    describe 'when the topic is not there yet' do
      let(:service) { PubSubModelSync::MockGoogleService.new(existing: false) }

      before do
        allow(Google::Cloud::PubSub).to receive(:new).and_return(service)
        allow(described_class.config).to receive(:logger).and_return(false)
      end

      it 'creates it' do
        described_class.new

        expect(service.created_topics).to include(service.topic_path('ps_sync'))
      end

      it 'connects to it once it is there' do
        expect(described_class.new.publishers.values.first).not_to be_nil
      end
    end
  end

  describe '.listen_messages' do
    it 'listens for new messages' do
      expect(inst.service.subscriber('ps_sync')).to receive(:listen).and_call_original
      inst.listen_messages
    end

    it 'starts the listener' do
      listener = inst.service.subscriber('ps_sync').listen
      expect(listener).to receive(:start)
      inst.listen_messages
    end

    it 'awaits for messages' do
      expect(inst).to receive(:sleep)
      inst.listen_messages
    end

    describe 'when the subscription is not there yet' do
      let(:service) { PubSubModelSync::MockGoogleService.new(existing: false) }

      before do
        allow(Google::Cloud::PubSub).to receive(:new).and_return(service)
        allow(described_class.config).to receive(:logger).and_return(false)
      end

      it 'creates it' do
        service_inst = described_class.new
        allow(service_inst).to receive(:sleep)

        service_inst.listen_messages

        expect(service.created_subscriptions.count).to eq 1
      end
    end
  end

  describe '.process_message' do
    let(:message_processor) { PubSubModelSync::MessageProcessor }

    before { allow(inst).to receive(:log) }

    it 'ignores if not a pub/sub model sync message (unknown)' do
      expect(message_processor).not_to receive(:new)
      inst.send(:process_message, mock_service_unknown_message)
    end

    describe 'when received a valid message' do
      it 'sends payload to message processor' do
        expect(message_processor).to receive(:new).and_call_original
        inst.send(:process_message, mock_service_message)
      end

      it 'acknowledges the message to mark as processed' do
        expect(mock_service_message).to receive(:acknowledge!)
        inst.send(:process_message, mock_service_message)
      end
    end

    describe 'when failed processing a message' do
      let(:error_msg) { 'Invalid params' }

      before { allow(message_processor).to receive(:new).and_raise(error_msg) }

      it 'raises the error' do
        expect { inst.send(:process_message, mock_service_message) }.to raise_error(error_msg)
      end

      it 'does not acknowledge the message to auto retry by pubsub' do
        expect(mock_service_message).not_to receive(:acknowledge!)
        inst.send(:process_message, mock_service_message) rescue nil # rubocop:disable Style/RescueModifier
      end
    end

    describe 'mark as received message' do
      it 'marks message as received when success' do
        expect(mock_service_message).to receive(:acknowledge!)
        inst.send(:process_message, mock_service_message)
      end

      it 'marks message as received even if failed' do
        expect(mock_service_message).to receive(:acknowledge!)
        allow(mock_message).to receive(:data).and_return('invalid_data')
        allow(inst).to receive(:log)
        inst.send(:process_message, mock_service_message)
      end

      it 'marks message as received even if unknown message' do
        expect(mock_service_unknown_message).to receive(:acknowledge!)
        inst.send(:process_message, mock_service_unknown_message)
      end
    end

    it 'says so when an unknown message arrives while debugging' do
      allow(described_class.config).to receive(:debug).and_return(true)

      expect(inst).to receive(:log).with(/Unknown message/)

      inst.send(:process_message, mock_service_unknown_message)
    end
  end

  describe '.publish' do
    let(:exp_headers) { hash_including('service_model_sync' => true) }

    it 'deliveries message' do
      expect(publisher)
        .to receive(:publish_async).with(payload.to_json, exp_headers, ordering_key: payload.ordering_key)
      inst.publish(payload)
    end

    it 'says so when the async publish came back succeeded while debugging' do
      allow(described_class.config).to receive(:debug).and_return(true)

      expect(inst).to receive(:log).with(/via async/).at_least(:once)

      inst.publish(payload)
    end

    it 'calls on_error_publish when failed publishing asynchronously (via thread)' do
      async_error = double(succeeded?: false, error: 'some error')
      allow(inst.config).to receive(:logger).and_return(false)
      allow(publisher).to receive(:publish_async) { |*_args, **_kwargs, &block| block.call(async_error) }
      expect(inst.config.on_error_publish).to receive(:call).with(anything, hash_including(:payload))
      inst.publish(payload)
    end

    describe 'when enabled sync_mode' do
      before { allow(inst.config).to receive(:sync_mode).and_return(true) }

      it 'uses defined ordering_key as the :ordering_key' do
        expect(publisher)
          .to receive(:publish).with(payload.to_json, exp_headers, ordering_key: payload.ordering_key)
        inst.publish(payload)
      end
    end

    it 'uses custom topic if defined' do
      payload.headers[:topic_name] = 'custom_topic_name'

      inst.publish(payload)

      expect(inst.publish_publishers.keys).to eq(['custom_topic_name'])
    end

    it 'publishes to all topics when defined' do
      payload.headers[:topic_name] = %w[topic1 topic2]

      inst.publish(payload)

      expect(inst.publish_publishers.keys).to eq(%w[topic1 topic2])
    end

    it 'publishes to the first topic it knows when the payload names none' do
      payload.headers[:topic_name] = ''
      allow(described_class.config).to receive(:default_topic_name).and_return(nil)

      expect(publisher).to receive(:publish_async)

      inst.publish(payload)
    end

    # https://github.com/googleapis/google-cloud-ruby/blob/main/google-cloud-pubsub/OVERVIEW.md#handling-errors-with-ordered-keys
    describe 'when failed because of OrderingKeyError (Ordered messages that fail to publish to the Pub/Sub API due
              to error will put the ordering_key in a failed state)' do
      before do
        error = Google::Cloud::PubSub::OrderingKeyError.new('some error')
        calls = 0
        allow(publisher).to receive(:publish_async) do
          (calls += 1) == 1 ? raise(error) : true
        end
        allow(described_class.config).to receive(:logger).and_return(false)
      end

      it 'calls #resume_publish on the publisher to re-enable publish for the ordering_key' do
        expect(publisher).to receive(:resume_publish).with(payload.headers[:ordering_key])
        inst.publish(payload)
      end

      it 'retries 1 time' do
        expect(publisher).to receive(:publish_async).exactly(2)
        inst.publish(payload)
      end

      it 'gives up once the retry fails too' do
        allow(publisher).to receive(:publish_async).and_raise(Google::Cloud::PubSub::OrderingKeyError.new('again'))

        expect { inst.publish(payload) }.to raise_error(Google::Cloud::PubSub::OrderingKeyError)
      end
    end
  end

  describe '.stop' do
    before { inst.listen_messages }

    it 'stops all listeners' do
      expect(inst.listeners.first).to receive(:stop!)
      inst.stop
    end
  end

  it 'ignores an unknown message silently when not debugging' do
    allow(described_class.config).to receive(:debug).and_return(false)

    expect(inst).not_to receive(:log)

    inst.send(:process_message, mock_service_unknown_message)
  end
end
