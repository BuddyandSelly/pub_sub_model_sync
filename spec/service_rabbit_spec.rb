# frozen_string_literal: true

RSpec.describe PubSubModelSync::ServiceRabbit do
  let(:meta_info) { { type: 'service_model_sync' } }
  let(:invalid_meta_info) { { type: 'unknown' } }
  let(:delivery_info) { {} }
  let(:msg_attrs) { { klass: 'User', action: 'action' } }
  let(:data) { { msg: 'Hello' } }
  let(:message) { { data: data, attributes: msg_attrs }.to_json }
  let(:inst) { described_class.new }
  let(:service) { inst.service }
  let(:channel) { service.channel }

  before { allow(inst).to receive(:loop) }

  describe 'initializer' do
    it 'connect to pub/sub service' do
      expect(service).not_to be_nil
    end
  end

  describe '.listen_messages' do
    after { inst.listen_messages }
    it 'start service' do
      expect(service).to receive(:start)
    end
    it 'create channel' do
      expect(service).to receive(:create_channel).and_call_original
    end
    it 'subscribe to queue' do
      expect(channel).to receive(:fanout).and_call_original
    end
    it 'subscribe to topic' do
      expect(channel).to receive(:topic).and_call_original
    end
    it 'listening messages' do
      expect(channel.queue).to receive(:subscribe)
    end
  end

  describe '.listen_messages when it goes wrong' do
    it 'lets a shut down through' do
      shut_down = PubSubModelSync::Runner::ShutDown
      allow(inst).to receive(:subscribe_to_queue).and_raise(shut_down)

      expect { inst.listen_messages }.to raise_error(shut_down)
    end

    it 'prints any other error' do
      error = 'Connection lost'
      allow(inst).to receive(:subscribe_to_queue).and_raise(error)
      allow(inst).to receive(:log)
      expect(inst).to receive(:log).with(include(error), :error)

      inst.listen_messages
    end
  end

  describe '.process_message' do
    let(:message_processor) { PubSubModelSync::MessageProcessor }
    it 'ignore unknown message' do
      expect(message_processor).not_to receive(:new)
      args = [delivery_info, invalid_meta_info, message]
      inst.send(:process_message, *args)
    end
    it 'process message' do
      args = [data, any_args]
      expect(message_processor).to receive(:new).with(*args).and_call_original
      args = [delivery_info, meta_info, message]
      inst.send(:process_message, *args)
    end
    it 'error processing' do
      error_msg = 'Invalid params'
      allow(message_processor).to receive(:new).and_raise(error_msg)
      expect(inst).to receive(:log).with(include(error_msg), :error)

      args = [delivery_info, meta_info, message]
      inst.send(:process_message, *args)
    end
    it 'ignore own message' do
      app_id = 'MyApplication'
      allow(inst).to receive(:app_id).and_return(app_id)
      expect(message_processor).not_to receive(:new)

      args = [delivery_info, meta_info.merge(app_id: app_id), message]
      inst.send(:process_message, *args)
    end
  end

  describe '.publish' do
    it 'delivery message' do
      data = { name: 'test' }
      attrs = { id: 10 }
      payload = { data: data, attributes: attrs }
      expected_args = [payload.to_json, hash_including(:routing_key, :type)]
      expect(channel.topic).to receive(:publish).with(*expected_args)
      inst.publish(data, attrs)
    end
    it 'print error when sending message' do
      error = 'Error msg'
      expect(channel.topic).to receive(:publish).and_raise(error)
      allow(inst).to receive(:log)
      expect(inst).to receive(:log).with(include(error), :error)
      inst.publish('invalid data', {})
    end
    it 'reconnect and retry after a timeout' do
      attempts = 0
      allow(inst).to receive(:deliver_data) do
        attempts += 1
        raise Timeout::Error if attempts == 1
      end
      allow(inst).to receive(:log)
      expect(inst).to receive(:log).with(include('retrying'), :error)

      inst.publish({ name: 'test' }, {})

      expect(attempts).to eq 2
    end
  end

  # Module#parent_name was removed in Rails 6.1, so this always rescues to an
  # empty string and the "skip messages published by this app" check in
  # .process_message never matches. Documented rather than changed: fixing it
  # changes which messages an application processes.
  describe '#app_id' do
    it 'is empty on Rails >= 6.1' do
      expect(inst.send(:app_id)).to eq ''
    end
  end

  describe '.stop' do
    it 'stop current subscription' do
      expect(service).to receive(:close)
      inst.stop
    end
  end
end
