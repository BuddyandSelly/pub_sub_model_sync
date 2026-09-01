# frozen_string_literal: true

RSpec.describe PubSubModelSync::Config do
  let(:msg) { 'test msg' }

  it 'ability to define configurations' do
    project_id = 'project_id'
    described_class.project = project_id
    expect(described_class.project).to eq project_id
  end

  describe '.log' do
    it 'log' do
      expect { described_class.log(msg) }.to output(include(msg)).to_stdout
    end

    context 'when the logger is :raise_error (as in this suite)' do
      it 'raises the message for errors' do
        expect { described_class.log(msg, :error) }
          .to raise_error(RuntimeError, /#{msg}/)
      end
    end

    context 'when a logger is configured' do
      let(:logger) { instance_double(Logger, info: true, error: true) }

      # the double may only be built inside the example
      around do |example|
        original = described_class.logger
        example.run
        described_class.logger = original
      end
      before { described_class.logger = logger }

      it 'logs through it' do
        expect(logger).to receive(:info).with(include(msg))
        described_class.log(msg)
      end

      it 'logs errors through it' do
        expect(logger).to receive(:error).with(include(msg))
        described_class.log(msg, :error)
      end
    end

    context 'without a logger' do
      around do |example|
        original = described_class.logger
        described_class.logger = nil
        example.run
        described_class.logger = original
      end

      it 'prints the message' do
        expect { described_class.log(msg) }.to output(include(msg)).to_stdout
      end
    end
  end
end
