# frozen-string-literal: true

require 'crack_pipe/action/exec'
require 'crack_pipe/action/result'
require 'crack_pipe/action/signal'
require 'crack_pipe/action/step'

module CrackPipe
  # NOTE: The reason for using an instantiated class rather than doing all of
  # this functionally, since there is no real state data, is so that symbols
  # operate as instance methods and that procs and the like are executed with
  # `instance_exec`, giving them access to the local scope.
  class Action
    @steps = []

    class << self
      attr_reader :steps

      def call(context, &blk)
        new(&blk).call(context)
      end

      # NOTE: In general, the only time you should use inheritence is when
      # created a more specilized generic action with some of its own methods
      # similar such as `pass!` or overiding behavior in `after_step` or
      # `failure?`.
      def inherited(subclass)
        subclass.instance_variable_set(:@steps, @steps.dup)
        super
      end

      private

      def fail(exec = nil, **kwargs, &blk)
        step(exec, kwargs.merge(track: :fail), &blk)
      end

      def pass(exec = nil, **kwargs, &blk)
        step(exec, kwargs.merge(always_pass: true), &blk)
      end

      def step(*args, &blk)
        @steps += [Step.new(*args, &blk)]
      end
    end

    attr_reader :steps

    def initialize(steps = nil, **default_context, &blk)
      @__default_context__ = default_context.dup
      @__wrapper__ = block_given? ? blk : nil
      @steps = steps ? steps.dup : self.class.steps
    end

    def call(context)
      context = @__default_context__.merge(context)
      return @__wrapper__.call(Exec.(self, context)) if @__wrapper__
      Exec.(self, context)
    end

    # NOTE: While this hook does nothing by default, it is here with the
    # intention of dealing with potential default values being generated either
    # for output or adding values to the context. A common example would be
    # returning some kind of default failure object in place of a literal `nil`
    # or `false`.
    def after_step(flow_control_hash)
      flow_control_hash
    end

    def fail!(output)
      Exec.halt(output, false)
    end

    def failure?(output)
      !output
    end

    def pass!(output)
      Exec.halt(output, true)
    end
  end
end