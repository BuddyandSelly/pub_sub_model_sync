# frozen_string_literal: true

RSpec.describe 'the pub_sub_model_sync:start rake task' do
  subject(:task) { worker_task }

  let(:runner) { instance_double(PubSubModelSync::Runner, run: true) }

  before { allow(PubSubModelSync::Runner).to receive(:new).and_return(runner) }

  it 'is described' do
    expect(task.full_comment).to eq('Start listening syncs')
  end

  it 'runs the listener' do
    task.execute

    expect(runner).to have_received(:run).once
  end

  # Each kafka consumer is assigned its own partitions, so the task starts a
  # listener per worker on top of the one of the main thread.
  describe 'when the service is kafka' do
    around do |example|
      abort_on_exception = Thread.current.abort_on_exception
      example.run
    ensure
      Thread.current.abort_on_exception = abort_on_exception
    end

    before do
      allow(PubSubModelSync::Config).to receive(:service_name).and_return(:kafka)
      allow(Thread).to receive(:new) { |&block| block.call }
    end

    it 'runs a listener per worker' do
      task.execute

      expect(runner)
        .to have_received(:run).exactly(PubSubModelSync::ServiceKafka::QTY_WORKERS).times
    end

    it 'lets a failed worker take the process down with it' do
      task.execute

      expect(Thread.current.abort_on_exception).to be true
    end
  end
end
