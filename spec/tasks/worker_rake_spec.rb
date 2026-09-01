# frozen_string_literal: true

RSpec.describe 'the pub_sub_model_sync:start rake task' do
  subject(:task) { worker_task }

  it 'is described' do
    expect(task.full_comment).to eq('Start listening syncs')
  end

  it 'runs the listener' do
    runner = instance_double(PubSubModelSync::Runner, run: true)
    allow(PubSubModelSync::Runner).to receive(:new).and_return(runner)

    task.execute

    expect(runner).to have_received(:run)
  end
end
