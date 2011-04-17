# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

module Popen

  def self.popen2(cmd, env = {})
    stdin_r, stdin_w = IO.pipe
    stdeo_r, stdeo_w = IO.pipe

    pid = fork
    if pid
      stdin_r.close
      stdeo_w.close

      yield stdin_w, stdeo_r

      Process.waitpid(pid, 0)
      proc_stat = $?
      return proc_stat.exitstatus
    else
      stdin_w.close
      stdeo_r.close

      $stdin.reopen(stdin_r)
      $stdout.reopen(stdeo_w)
      $stderr.reopen(stdeo_w)

      update_env(env)
      exec cmd
    end
  end

  def self.popen3(cmd, env = {})
    stdin_r,  stdin_w  = IO.pipe
    stdout_r, stdout_w = IO.pipe
    stderr_r, stderr_w = IO.pipe

    pid = fork
    if pid 
      stdin_r.close
      stdout_w.close
      stderr_w.close

      yield stdin_w, stdout_r, stderr_r

      Process.waitpid(pid, 0)
      proc_stat = $?
      return proc_stat.exitstatus
    else 
      stdin_w.close
      stdout_r.close
      stderr_r.close

      $stdin.reopen(stdin_r)
      $stdout.reopen(stdout_w)
      $stderr.reopen(stderr_w)

      update_env(env)
      exec cmd
    end
  end

  private

  def self.update_env(env)
    ENV.delete_if do |key, value|
      not (
        key.start_with?('XPACK_') || ['PATH', 'USER', 'USERNAME'].include?(key)
      )
    end
    env.each_pair do |key, value|
      ENV[key] = value
    end
  end

end
