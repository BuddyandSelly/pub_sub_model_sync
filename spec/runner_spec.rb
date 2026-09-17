# frozen_string_literal: true

RSpec.describe PubSubModelSync::Runner do
  let(:inst) { described_class.new }
  let(:connector_klass) { PubSubModelSync::Connector }
  let(:connector) { inst.connector }
  before { allow(inst.connector).to receive(:listen_messages) }
  after { inst.run }

  it '.trap_signals' do
    allow(Signal).to receive(:trap)
    expect(Signal).to receive(:trap).with('QUIT', anything)
  end

  it '.preload_framework' do
    expect(described_class).to receive(:preload_listeners)
  end

  it '.start_listeners' do
    expect(connector).to receive(:listen_messages)
  end

  describe '.preload_listeners' do
    # The gem also runs outside rails, and only preloads what is there
    it 'preloads what the host application offers' do
      hide_const('Rails')
      loader = double('Zeitwerk::Loader', eager_load_all: true)
      stub_const('Zeitwerk::Loader', loader)

      described_class.preload_listeners

      expect(loader).to have_received(:eager_load_all)
    end
  end

  it 'stops the process when it is signalled' do
    handler = nil
    allow(Signal).to receive(:trap) { |_signal, signal_handler| handler = signal_handler }
    allow(inst).to receive(:puts)

    inst.send(:trap_signals!)

    expect { handler.call(Signal.list['TERM']) }.to raise_error(SystemExit)
    expect(inst).to have_received(:puts).with(include('received TERM'))
  end
end
