require 'ostruct'
require 'aws-sdk'
require 'spec_helper'

TEST_STACK_NAME = "test-stack"

now = Time.now

describe Bora::Stack do
  before :each do
    @cfn = double(Aws::CloudFormation::Client)
    allow(Aws::CloudFormation::Client).to receive(:new).and_return(@cfn)
    @stack = Bora::Stack.new(TEST_STACK_NAME)
  end

  context "when the stack does not exist" do
    def expect_create_stack(options)
      allow(@cfn).to receive(:describe_stack_events).and_return(describe_stack_events_result(reason: "just because"))
      expect(@cfn).to receive(:create_stack).with(options) do
        allow(@cfn).to receive(:describe_stacks).and_return(describe_stacks_result)
      end
    end

    before :each do
      allow(@cfn).to receive(:describe_stacks).and_raise(Aws::CloudFormation::Errors::ValidationError.new("Stack does not exist", "Error"))
    end

    describe "#exists?" do
      it "returns false" do
        expect(@stack.exists?).to be_falsy
      end
    end

    describe "#create" do
      it "creates the stack" do
        options = { template_body: '{"foo": "bar"}' }
        expect_create_stack(options)
        @stack.create(options) { |e| expect(e.resource_status_reason).to eq("just because") }
      end
    end

    describe "#recreate" do
      it "behaves the same as create" do
        options = { template_body: '{"foo": "bar"}' }
        expect_create_stack(options)
        expect(@cfn).to_not receive(:delete_stack)
        @stack.recreate(options)
      end
    end

    describe "#create_or_update" do
      it "calls create" do
        options = { template_body: '{"foo": "bar"}' }
        expect_create_stack(options)
        @stack.create_or_update(options)
      end
    end

    describe "#delete" do
      it "doesn't fail" do
        expect(@cfn).to_not receive(:delete_stack)
        expect(@stack.delete).to be_truthy
      end
    end

    describe "#events" do
      it "returns and empty list" do
        expect(@stack.events.length).to eq(0)
      end
    end

    describe "#template" do
      it "returns nil" do
        expect(@stack.template).to be_nil
      end
    end

    describe "#diff" do
      it "doesn't fail" do
        expect(@stack.diff({template_body: '{"foo": "bar"}'})).to_not be_nil
      end
    end

    describe "#status" do
      it "return an object representing the current status of the stack" do
        expect(@stack.status.exists?).to be_falsey
      end
    end

  end

  context "when the stack exists" do
    before :each do
      allow(@cfn).to receive(:describe_stacks).and_return(describe_stacks_result)
      allow(@cfn).to receive(:describe_stack_events).and_return(describe_stack_events_result(timestamp: now - 60), describe_stack_events_result(reason: "just because"))
    end

    describe "#exists?" do
      it "returns true" do
        expect(@stack.exists?).to be true
      end
    end

    describe "#update" do
      it "updates the stack" do
        options = { stack_name: TEST_STACK_NAME, template_body: "foo" }
        expect(@cfn).to receive(:update_stack).with(options)
        @stack.update(options) { |e| expect(e.resource_status_reason).to eq("just because") }
      end
    end

    describe "#recreate" do
      it "deletes and then creates the stack" do
        expect(@cfn).to receive(:delete_stack) do
          allow(@cfn).to receive(:describe_stacks).and_raise(Aws::CloudFormation::Errors::ValidationError.new("Stack does not exist", "Error"))
          allow(@cfn).to receive(:describe_stack_events).and_return(describe_stack_events_result(timestamp: now-50), describe_stack_events_result)
        end
        expect(@cfn).to receive(:create_stack) do
          allow(@cfn).to receive(:describe_stacks).and_return(describe_stacks_result)
        end
        @stack.recreate({template_body: "foo"})
      end
    end

    describe "#create_or_update" do
      it "calls update" do
        expect(@cfn).to receive(:update_stack)
        @stack.create_or_update({})
      end
    end

    describe "#delete" do
      it "deletes the stack" do
        expect(@cfn).to receive(:delete_stack)
        @stack.delete
      end
    end

    describe "#events" do
      it "returns all events" do
        expect(@cfn).to receive(:describe_stack_events).and_return(describe_stack_events_result(count: 2))
        expect(@stack.events.length).to eq(2)
      end
    end

    describe "#template" do
      it "returns the current stack template" do
        expect(@cfn).to receive(:get_template).at_least(:once).and_return(OpenStruct.new(template_body: '{"foo": "bar"}'))
        expect(@stack.template(false)).to eq('{"foo": "bar"}')
        expect(@stack.template(true).include?("\n")).to be true
      end
    end

    describe "#diff" do
      it "should return a diff of the current and new templates" do
        current_template = "{\n\"foo\": \"bar\"\n}"
        new_template = "{\n\"foo\": \"barx\"\n}"
        expect(@cfn).to receive(:get_template).and_return(OpenStruct.new(template_body: current_template))
        expect(@stack.diff({template_body: new_template}).to_s).to include "+  \"foo\": \"barx\""
      end
    end

    describe "#status" do
      it "return an object representing the current status of the stack" do
        expect(@stack.status.exists?).to be_truthy
      end
    end
  end

  describe "#new_template" do
    it "returns the template body" do
      template = '{"foo": "bar"}'
      expect(@stack.new_template({template_body: template}, false)).to eq(template)
      expect(@stack.new_template({template_body: template}).include?("\n")).to be true
    end
  end

  describe "#validate" do
    it "calls aws to validate the template" do
      expect(@cfn).to receive(:validate_template).with({template_body: "foo"})
      @stack.validate({template_body: "foo", this: "should not get passed"})
    end
  end

  describe "any update action" do
    it "treats rollbacks as failures" do
      allow(@cfn).to receive(:describe_stacks).and_return(describe_stacks_result(status: "ROLLBACK_COMPLETE"))
      allow(@cfn).to receive(:describe_stack_events).and_return(
        describe_stack_events_result(timestamp: now - 60), describe_stack_events_result(status: "ROLLBACK_COMPLETE"))
      @stack = Bora::Stack.new(TEST_STACK_NAME)
      expect(@cfn).to receive(:update_stack)
      result = @stack.update({template_body: "foo"})
      expect(result).to be_falsey
    end
  end

end
