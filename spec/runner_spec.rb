# frozen_string_literal: true

RSpec.describe PubSubModelSync::Runner do
  let(:inst) { described_class.new }
  let(:connector) { inst.connector }
  before { allow(connector).to receive(:listen_messages) }

  it '.trap_signals' do
    allow(Signal).to receive(:trap)
    expect(Signal).to receive(:trap).with('QUIT', anything)
    inst.run
  end

  it '.preload_framework' do
    expect(inst).to receive(:preload_framework!)
    inst.run
  end

  it '.start_listeners' do
    expect(connector).to receive(:listen_messages)
    inst.run
  end

  it 'shutdown' do
    error_klass = PubSubModelSync::Runner::ShutDown
    allow(inst).to receive(:trap_signals!).and_raise(error_klass)
    expect(connector).to receive(:stop)
    inst.run
  end

  describe 'trapped signals' do
    let(:handlers) { {} }

    before do
      allow(Signal).to receive(:trap) { |signal, handler|
        handlers[signal] = handler
      }
    end

    it 'listens for the signals that stop a worker' do
      inst.run

      expect(handlers.keys).to eq(%w[INT QUIT TERM])
    end

    it 'stops the connector when one of them is received' do
      # the handler runs while the runner is starting up
      allow(inst).to receive(:preload_framework!) do
        handlers['TERM'].call(Signal.list['TERM'])
      end
      expect(connector).to receive(:stop)

      expect { inst.run }.to output(include('received TERM')).to_stdout
    end
  end

  describe 'preloading the framework' do
    it 'eager loads the Rails application' do
      application = double('Rails.application', eager_load!: true)
      stub_const('Rails', double('Rails', application: application))

      inst.run

      expect(application).to have_received(:eager_load!)
    end

    it 'eager loads every zeitwerk loader' do
      loader = double('Zeitwerk::Loader', eager_load_all: true)
      stub_const('Zeitwerk::Loader', loader)

      inst.run

      expect(loader).to have_received(:eager_load_all)
    end

    it 'does nothing without Rails and zeitwerk' do
      hide_const('Rails')

      expect(connector).to receive(:listen_messages)
      inst.run
    end
  end
end
