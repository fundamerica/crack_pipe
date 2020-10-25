# frozen-string-literal: true

require 'crack_pipe/action/signal'

module CrackPipe
  class Action
    module Exec
      class << self
        def call(action, context, track = :default)
          Result.new(action(action, context, track))
        end

        def action(action, context, track = :default, current_step_index = 0, results = [])
          steps = action.class.steps
          return results if current_step_index == steps.size

          current_step = steps[current_step_index]

          if track == current_step.track
            results!(results, action, current_step, context).last.tap do |output|
              action.after_flow_control(output)
              context = output[:context]
              track = output[:next]
              return results if output[:signal] == :halt
            end
          end

          action(action, context, track, current_step_index + 1, results)
        end

        def flow_control_hash(action, step, context, output)
          success = success_with_step?(action, step, output)

          {
            exec: step.exec,
            track: step.track,
            next: success ? step.track : :fail,
            context: context.dup
          }.merge(flow_control_with_output(output, success))
        end

        def flow_control_with_output(output, success)
          case output
          when Signal
            {
              signal: output.type,
              output: output.value,
              success: output.success.nil? ? success : output.success
            }
          else
            { output: output, success: success }
          end
        end

        def halt(output, success = nil)
          throw(:signal, Signal.new(:halt, output, success))
        end

        def step(action, step, context)
          kwargs = kwargs_with_context(action, context)

          return :skipped unless should_exec?(step.exec_if, action, context, kwargs)

          output = catch(:signal) do
            exec_with_args(step.exec, action, context, kwargs)
          end

          action.after_step(output)
        end

        def success_with_step?(action, step, output)
          step.always_pass? || step.track != :fail && !action.failure?(output)
        end

        private

        def callable?(e)
          e.is_a?(Symbol) || e.respond_to?(:call)
        end

        def should_exec?(exec_if, action, context, kwargs)
          return exec_with_args(exec_if, action, context.dup, kwargs) if callable?(exec_if)

          exec_if
        end

        def exec_with_args(e, action, context, kwargs)
          if e.is_a?(Symbol)
            action.public_send(e, context, **kwargs)
          else
            e.call(context, **kwargs)
          end
        end

        def kwargs_with_context(action, context)
          return context if action.kwargs_overrides.empty?

          context.merge(action.kwargs_overrides)
        end

        def results!(results, action, step, context)
          o = step(action, step, context)
          return results.concat(o.history) if o.is_a?(Result)

          results << flow_control_hash(action, step, context, o)
        end
      end
    end
  end
end
