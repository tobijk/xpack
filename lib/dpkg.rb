# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'popen'

module Dpkg

  def which_package_provides(filename)
    result = nil
    cmd = "dpkg -S #{File.expand_path(filename)}"
      exit_status = Popen.popen2(cmd) do |stdin, stdeo|
      stdin.close
      result = stdeo.read.split(':', 2)[0]
    end
    if exit_status != 0
      return nil
    else
      return result.strip
    end
  end

  def installed_version_of_package(package_name)
    result = nil
    cmd = "dpkg-query -W --showformat '${Version}' #{package_name}"
    exit_status = Popen.popen2(cmd) do |stdin, stdeo|
      stdin.close
      result = stdeo.read
    end

    return nil if exit_status != 0 || result.strip.empty?

    # extract components, we need epoch and upstream version
    version = result.match(/^(?:(\d+):)?([-.+~a-zA-Z0-9]+?)(?:-([.~+a-zA-Z0-9]+)){0,1}$/)
    epoch, upstream, release = version[1,4]

    unless epoch.nil?
      return "#{epoch}:#{upstream}"
    else
      return "#{upstream}"
    end
  end

  def installed_version_meets_condition?(package_name, condition)
    installed_version = self.installed_version_of_package(package_name)

    return false if installed_version.nil?
    return true  if condition.nil? || condition.empty?

    # extract operator and version
    begin
      operator, version = condition.match(/^(<<|<=|=|>=|>>)\s*(\S+)$/)[1,2]
    rescue
      raise StandardError, "invalid dependency specification '#{condition}'"
    end

    operator_map = {
      '<<' => 'lt-nl',
      '<=' => 'le-nl',
      '='  => 'eq',
      '>=' => 'ge-nl',
      '>>' => 'gt-nl'
    }

    operator = operator_map[operator]

    cmd = "dpkg --compare-versions '#{installed_version}' '#{operator}' '#{version}'"
    exit_status = Popen.popen2(cmd) do |stdin, stdeo|
      stdin.close
      stdeo.reopen('/dev/null', 'w')
    end

    exit_status == 0 ? true : false
  end

end

