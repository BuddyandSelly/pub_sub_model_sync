# frozen_string_literal: true

RSpec.describe PubSubModelSync::Config do
  it 'permits to define configurations' do
    project_id = 'project_id'
    described_class.project = project_id
    expect(described_class.project).to eq project_id
  end

  it 'logs to stdout' do
    msg = 'test msg'
    expect { described_class.log(msg) }.to output(include(msg)).to_stdout
  end

  it 'logs to the configured logger' do
    logger = instance_double(Logger, info: true)
    allow(described_class).to receive(:logger).and_return(logger)

    described_class.log('test msg')

    expect(logger).to have_received(:info).with(include('test msg'))
  end

  describe '.subscription_key' do
    # Rails renamed Module#parent_name to #module_parent_name in 6.0
    it 'names the application of a rails older than the rename' do
      klass = Class.new do
        singleton_class.send(:undef_method, :module_parent_name)

        def self.parent_name
          'OldApp'
        end
      end
      allow(Rails).to receive(:application).and_return(klass.new)
      allow(described_class).to receive(:subscription_name).and_return(nil)

      expect(described_class.subscription_key).to eq('OldApp')
    end
  end
end
