#
# Author:: Noah Kantrowitz <noah@opscode.com>
# Cookbook Name:: supervisor
# Resource:: service
#
# Copyright:: 2011, Opscode, Inc <legal@opscode.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

resource_name :supervisor_service

default_action :enable

property :service_name, String, name_property: true
property :command, String
property :process_name, String, default: '%(program_name)s'
property :numprocs, Integer, default: 1
property :numprocs_start, Integer, default: 0
property :priority, Integer, default: 999
property :autostart, [TrueClass, FalseClass], default: true
property :autorestart, [String, Symbol, TrueClass, FalseClass], default: :unexpected
property :startsecs, Integer, default: 1
property :startretries, Integer, default: 3
property :exitcodes, Array, default: [0, 2]
property :stopsignal, [String, Symbol], default: :TERM
property :stopwaitsecs, Integer, default: 10
property :stopasgroup, [TrueClass,FalseClass,NilClass], default: nil
property :killasgroup, [TrueClass,FalseClass,NilClass], default: nil
property :user, [String, NilClass], default: nil
property :redirect_stderr, [TrueClass, FalseClass], default: false
property :stdout_logfile, String, default: 'AUTO'
property :stdout_logfile_maxbytes, String, default: '50MB'
property :stdout_logfile_backups, Integer, default: 10
property :stdout_capture_maxbytes, String, default: '0'
property :stdout_events_enabled, [TrueClass, FalseClass], default: false
property :stderr_logfile, String, default: 'AUTO'
property :stderr_logfile_maxbytes, String, default: '50MB'
property :stderr_logfile_backups, Integer, default: 10
property :stderr_capture_maxbytes, String, default: '0'
property :stderr_events_enabled, [TrueClass, FalseClass], default: false
property :environment, Hash, default: {}
property :directory, [String, NilClass], default: nil 
property :umask, [NilClass, String], default: nil
property :serverurl, String, default: 'AUTO'

property :eventlistener, [TrueClass,FalseClass], default: false
property :eventlistener_buffer_size, [Integer, NilClass], default: nil
property :eventlistener_events, Array, default: []

attr_accessor :state

load_current_value do
  @state = get_current_state(service_name)
end

action :enable do
  e = execute "supervisorctl update" do
    action :nothing
    user "root"
  end

  t = template "#{node['supervisor']['dir']}/#{new_resource.service_name}.conf" do
    source "program.conf.erb"
    cookbook "supervisor"
    owner "root"
    group "root"
    mode "644"
    variables :prog => new_resource
    notifies :run, "execute[supervisorctl update]", :immediately
  end

  t.run_action(:create)
  if t.updated?
    e.run_action(:run)
  end
end

action :start do
  case @current_resource.state
  when 'UNAVAILABLE'
    raise "Supervisor service #{new_resource.name} cannot be started because it does not exist"
  when 'RUNNING'
    Chef::Log.debug "#{ new_resource } is already started."
  when 'STARTING'
    Chef::Log.debug "#{ new_resource } is already starting."
    wait_til_state("RUNNING", 20, new_resource)
  else
    if not supervisorctl('start', new_resource)
      raise "Supervisor service #{new_resource.name} was unable to be started"
    end
  end
end

action :restart do
  case @current_resource.state
  when 'UNAVAILABLE'
    raise "Supervisor service #{new_resource.name} cannot be restarted because it does not exist"
  else
    if not supervisorctl('restart', new_resource)
      raise "Supervisor service #{new_resource.name} was unable to be started"
    end
  end
end

action :stop do
  case @current_resource.state
  when 'UNAVAILABLE'
    raise "Supervisor service #{new_resource.name} cannot be stopped because it does not exist"
  when 'STOPPED'
    Chef::Log.debug "#{ new_resource } is already stopped."
  when 'STOPPING'
    Chef::Log.debug "#{ new_resource } is already stopping."
    wait_til_state("STOPPED", 20, new_resource)
  else
    if not supervisorctl('stop', new_resource)
      raise "Supervisor service #{new_resource.name} was unable to be stopped"
    end
  end
end


action :disable do
  if @current_resource.state == 'UNAVAILABLE'
    Chef::Log.info "#{new_resource} is already disabled."
  else
    execute "supervisorctl update" do
      action :nothing
      user "root"
    end

    file "#{node['supervisor']['dir']}/#{new_resource.service_name}.conf" do
      action :delete
      notifies :run, "execute[supervisorctl update]", :immediately
    end
  end
end


def get_current_state(service_name)
  result = shell_out("supervisorctl status")
  match = result.stdout.match("(^#{service_name}(\\:\\S+)?\\s*)([A-Z]+)(.+)")

  if match.nil?
    "UNAVAILABLE"
  else
    match[3]
  end
end

def supervisorctl(action, new_resource)
  cmd = "supervisorctl #{action} #{cmd_line_args(new_resource)} | grep -v ERROR"
  result = shell_out(cmd).run_command
  # Since we append grep to the command
  # The command will have an exit code of 1 upon failure
  # So 0 here means it was successful
  result.exitstatus == 0
end

def cmd_line_args(new_resource)
  name = new_resource.service_name
  if new_resource.process_name != '%(program_name)s'
    name += ':*'
  end
  name
end

def wait_til_state(state, max_tries = 20, new_resource)
  service = new_resource.service_name

  max_tries.times do
    return if get_current_state(service) == state

    Chef::Log.debug("Waiting for service #{service} to be in state #{state}")
    sleep 1
  end

  raise "service #{service} not in state #{state} after #{max_tries} tries"
end

