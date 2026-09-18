# frozen_string_literal: true

RSpec.describe PubSubModelSync::Railtie do
  it 'is a Rails railtie' do
    expect(described_class.superclass).to be(Rails::Railtie)
  end

  it 'is named after the gem' do
    expect(described_class.railtie_name).to eq('pub_sub_model_sync')
  end

  it 'registers the rake tasks of the gem' do
    expect(described_class)
      .to receive(:load).with('pub_sub_model_sync/tasks/worker.rake')

    described_class.rake_tasks.each(&:call)
  end
end
