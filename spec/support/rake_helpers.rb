# frozen_string_literal: true

require 'rake'

##
# The gem ships a rake task that Rails picks up through the railtie.
#
# `Kernel#load` resets the coverage counters of the file it loads, so the task
# definition is loaded exactly once for the whole suite.
module RakeHelpers
  def worker_task
    RakeHelpers.worker_task
  end

  def self.worker_task
    @worker_task ||= begin
      # rake only records descriptions when it is asked to list tasks
      Rake::TaskManager.record_task_metadata = true
      load 'pub_sub_model_sync/tasks/worker.rake'
      Rake::Task['pub_sub_model_sync:start']
    end
  end
end

RSpec.configure do |config|
  config.include RakeHelpers
end
