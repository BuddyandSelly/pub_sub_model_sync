# frozen_string_literal: true

RSpec.describe PubSubModelSync::ServiceBase do
  let(:inst) { described_class.new }

  describe 'the interface a service has to implement' do
    %i[listen_messages publish stop].each do |method|
      it "requires .#{method}" do
        args = if described_class.instance_method(method).arity.zero?
                 []
               else
                 [{},
                  {}]
               end

        expect { inst.send(method, *args) }
          .to raise_error(RuntimeError, /method :#{method} must be defined/)
      end
    end
  end
end
