require 'honeybadger/agent'
require 'timecop'

describe Honeybadger::Agent do
  NULL_BLOCK = Proc.new{}.freeze

  describe "class methods" do
    subject { described_class }

    its(:instance) { should be_a(Honeybadger::Agent) }
  end

  describe "#check_in" do

    it 'parses check_in id from a url' do
      stub_request(:get, "https://api.honeybadger.io/v1/check_in/1MqIo1").
         to_return(status: 200)

      config = Honeybadger::Config.new(api_key:'fake api key', logger: NULL_LOGGER)
      instance = described_class.new(config)

      instance.check_in('https://api.honeybadger.io/v1/check_in/1MqIo1')
    end

    it 'returns true for successful check ins' do
      stub_request(:get, "https://api.honeybadger.io/v1/check_in/foobar").
         to_return(status: 200)

      config = Honeybadger::Config.new(api_key:'fake api key', logger: NULL_LOGGER)
      instance = described_class.new(config)

      expect(instance.check_in('foobar')).to eq(true)
      expect(instance.check_in('/foobar')).to eq(true)
      expect(instance.check_in('/foobar/')).to eq(true)
    end

    it 'returns false for failed check ins' do
      stub_request(:get, "https://api.honeybadger.io/v1/check_in/danny").
         to_return(status: 400)

      config = Honeybadger::Config.new(api_key:'fake api key', logger: NULL_LOGGER)
      instance = described_class.new(config)

      expect(instance.check_in('danny')).to eq(false)
    end
  end

  describe "#notify" do
    it "generates a backtrace" do
      config = Honeybadger::Config.new(api_key:'fake api key', logger: NULL_LOGGER)
      instance = described_class.new(config)

      expect(instance.worker).to receive(:push) do |notice|
        expect(notice.backtrace.to_a[0][:file]).to eq('[PROJECT_ROOT]/spec/unit/honeybadger/agent_spec.rb')
      end

      instance.notify(error_message: 'testing backtrace generation')
    end

    it "calls all of the before notify hooks before sending" do
      hooks = [spy("hook one", arity: 1), spy("hook two", arity: 1), spy("hook three", arity: 1)]
      instance = described_class.new(Honeybadger::Config.new(api_key: "fake api key", logger: NULL_LOGGER))
      instance.configure do |config|
        hooks.each { |hook| config.before_notify(hook) }
      end

      instance.notify(error_message: "testing before notify hooks")

      hooks.each do |hook|
        expect(hook).to have_received(:call).with(instance_of(Honeybadger::Notice))
      end
    end

    it "continues processing even if a before notify hook throws an error" do
      hook = ->(notice) { raise ArgumentError, "this was incorrect" }
      instance = described_class.new(Honeybadger::Config.new(api_key: "fake api key", logger: NULL_LOGGER))
      instance.configure do |config|
        config.before_notify(hook)
      end

      expect { instance.notify(error_message: "testing error-raising before notify hook") }.not_to raise_error
    end

    it "halts the callback chain when a notice is halted" do
      before_halt_hooks = [spy("hook one", arity: 1), spy("hook two", arity: 1)]
      halt_hook = ->(notice) { notice.halt! }
      after_halt_hooks = [spy("hook three", arity: 1), spy("hook four", arity: 1)]
      instance = described_class.new(Honeybadger::Config.new(api_key: "fake api key", logger: NULL_LOGGER))
      instance.configure do |config|
        before_halt_hooks.each { |hook| config.before_notify(hook) }
        config.before_notify(halt_hook)
        after_halt_hooks.each { |hook| config.before_notify(hook) }
      end

      instance.notify(error_message: "testing error-raising before notify hook")

      before_halt_hooks.each do |hook|
        expect(hook).to have_received(:call).with(instance_of(Honeybadger::Notice))
      end

      after_halt_hooks.each do |hook|
        expect(hook).not_to have_received(:call).with(instance_of(Honeybadger::Notice))
      end
    end

  end

  context do
    let!(:instance) { described_class.new(config) }
    let(:config) { Honeybadger::Config.new(logger: NULL_LOGGER, debug: true) }

    subject { instance }

    before do
      allow(config.logger).to receive(:debug)
    end

    after { instance.stop(true) }

    describe "#initialize" do
      describe "#worker" do
        subject { instance.worker }

        it { should be_a Honeybadger::Worker }
      end
    end

    describe "#flush" do
      subject { instance.flush(&block) }

      context "when no block is given" do
        let(:block) { nil }
        it { should eq true }

        it "flushes worker" do
          expect(instance.worker).to receive(:flush)
          subject
        end
      end

      context "when no block is given" do
        let(:block) { Proc.new { expecting.call } }
        let(:expecting) { double(call: true) }

        it { should eq true }

        it "executes the block" do
          expect(expecting).to receive(:call)
          subject
        end

        it "flushes worker" do
          expect(instance.worker).to receive(:flush)
          subject
        end
      end

      context "when an exception occurs" do
        let(:block) { Proc.new { fail 'oops' } }

        it "flushes worker" do
          expect(instance.worker).to receive(:flush)
          expect { subject }.to raise_error /oops/
        end
      end
    end

    describe "#exception_filter" do
      it "configures the exception_filter callback" do
        expect { instance.exception_filter(&NULL_BLOCK) }.to change(instance.config, :exception_filter).from(nil).to(NULL_BLOCK)
      end
    end

    describe "#exception_fingerprint" do
      it "configures the exception_fingerprint callback" do
        expect { instance.exception_fingerprint(&NULL_BLOCK) }.to change(instance.config, :exception_fingerprint).from(nil).to(NULL_BLOCK)
      end
    end

    describe "#backtrace_filter" do
      it "configures the backtrace_filter callback" do
        expect { instance.backtrace_filter(&NULL_BLOCK) }.to change(instance.config, :backtrace_filter).from(nil).to(NULL_BLOCK)
      end
    end
  end
end
