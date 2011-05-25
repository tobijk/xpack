# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'popen'

class Dpkg

  STATUS_FILE = '/var/lib/dpkg/status'

  def initialize
    @packages = {}

    status_list = File.open(Dpkg::STATUS_FILE, 'r') do |f|
      f.read
    end

    package_list = status_list.split(/\n\n+/)

    package_list.each do |pkg|
      meta_data = {}
      pkg.each_line do |line|
        if line.match(/^(Package|Version|Provides|Status):\s*(.*)/)
          meta_data[$1.downcase.intern] = $2.strip
        end
      end

      if meta_data[:status] =~ /install\s+ok\s+installed/
        @packages[meta_data[:package]] = meta_data[:version]
        if meta_data[:provides]
          provides = meta_data[:provides].split(/\s*,\s*/)
          provides.each do |name|
            @packages[name] = '' if @packages[name].nil?
          end
        end
      end
    end
  end

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
    return @packages[package_name]
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

