# frozen_string_literal: true

RSpec.describe PubSubModelSync::ServiceGoogle do
  let(:msg_attrs) { { 'service_model_sync' => true } }
  let(:message_data) { { data: {}, attributes: {} } }
  let(:mock_message) do
    double('Message', data: message_data.to_json, attributes: msg_attrs)
  end
  let(:mock_service_message) do
    double('ServiceMessage', message: mock_message, acknowledge!: true)
  end
  let(:mock_service_unknown_message) do
    mock_message.attributes['service_model_sync'] = nil
    mock_service_message
  end
  let(:inst) { described_class.new }
  before { allow(inst).to receive(:sleep) }

  let(:not_found) { Google::Cloud::NotFoundError.new('not found') }

  describe 'initializer' do
    it 'connect to pub/sub service' do
      expect(inst.service).not_to be_nil
    end
    it 'connect to topic' do
      expect(inst.topic).not_to be_nil
    end
    it 'creates the topic when the project does not have one yet' do
      service = PubSubModelSync::MockGoogleService.new
      allow(Google::Cloud::Pubsub).to receive(:new).and_return(service)
      allow(service).to receive(:publisher)
        .and_invoke(->(*) { raise not_found }, ->(*) { 'publisher' })
      expect(service.topic_admin).to receive(:create_topic)
      expect(described_class.new.topic).to eq('publisher')
    end
  end

  describe '.listen_messages' do
    it 'subscribe to topic' do
      expect(inst.service).to receive(:subscriber).and_call_original
      inst.listen_messages
    end
    it 'subscription listen for new messages' do
      expect(inst.service.subscriber).to receive(:listen).and_call_original
      inst.listen_messages
    end
    it 'start subscriber' do
      subscriber = inst.service.subscriber.listen
      expect(subscriber).to receive(:start)
      inst.listen_messages
    end
    it 'wait for messages' do
      expect(inst).to receive(:sleep)
      inst.listen_messages
    end
    it 'creates the subscription when the topic does not have one yet' do
      subscriber = PubSubModelSync::MockGoogleService::MockSubscriber.new
      allow(inst.service).to receive(:subscriber)
        .and_invoke(->(*) { raise not_found }, ->(*) { subscriber })
      expect(inst.service.subscription_admin).to receive(:create_subscription)
      inst.listen_messages
    end
  end

  describe '.process_message' do
    let(:message_processor) { PubSubModelSync::MessageProcessor }
    it 'ignore if not a pub/sub model sync message (unknown)' do
      expect(message_processor).not_to receive(:new)
      inst.send(:process_message, mock_service_unknown_message)
    end
    it 'process message' do
      expect(message_processor).to receive(:new).and_call_original
      inst.send(:process_message, mock_service_message)
    end
    it 'error processing' do
      error_msg = 'Invalid params'
      allow(message_processor).to receive(:new).and_raise(error_msg)
      expect(inst).to receive(:log).with(include(error_msg), :error)
      inst.send(:process_message, mock_service_message)
    end

    describe 'mark as received message' do
      it 'when success' do
        expect(mock_service_message).to receive(:acknowledge!)
        inst.send(:process_message, mock_service_message)
      end
      it 'when error' do
        expect(mock_service_message).to receive(:acknowledge!)
        allow(mock_message).to receive(:data).and_return('invalid_data')
        allow(inst).to receive(:log)
        inst.send(:process_message, mock_service_message)
      end
      it 'when unknown message' do
        expect(mock_service_unknown_message).to receive(:acknowledge!)
        inst.send(:process_message, mock_service_unknown_message)
      end
    end
  end

  describe '.publish' do
    it 'delivery message' do
      data = { name: 'test' }
      attrs = { id: 10 }
      payload = { data: data, attributes: attrs }.to_json
      expect(inst.topic).to receive(:publish).with(payload, anything)
      inst.publish(data, attrs)
    end
    it 'print error when sending message' do
      error = 'Error msg'
      allow(inst.topic).to receive(:publish).and_raise(error)
      allow(inst).to receive(:log)
      expect(inst).to receive(:log).with(include(error), :error)
      inst.publish({}, {})
    end
  end

  describe '.stop' do
    before { inst.listen_messages }
    it 'stop current subscription' do
      expect(inst.subscriber).to receive(:stop!)
      inst.stop
    end
  end
end
