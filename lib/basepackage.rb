# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Generator
# Copyright (C) 2010-2011, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'packagemanager'

class BasePackage

  class Dependency
    attr_accessor :name, :version

    def initialize(name, version = nil)
      @name = name
      @version = version
    end

    def fulfilled?
      package_manager = PackageManager.instance
      package_manager.installed_version_meets_condition?(@name, @version)
    end

  end

  class DependencySpecification
    attr_reader :list, :index

    def initialize
      @list  = []
      @index = {}
    end

    def self.from_xml(xml_config = "")
      spec = BasePackage::DependencySpecification.new

      case xml_config
        when Nokogiri::XML::Element
          dep_node = xml_config
        when String
          dep_node = Nokogiri::XML(xml_config).root
        else
          return spec
      end

      dep_node.xpath('package|choice').each do |node|
        alternatives = []
        if node.name == 'choice'
          node.xpath('package').each do |pkg|
            alternatives << BasePackage::Dependency.new(
              pkg['name'], pkg['version'])
          end
        else
          alternatives << BasePackage::Dependency.new(
            node['name'], node['version'])
        end
        alternatives.each { |dep| spec.index[dep.name] = dep }
        spec.list << alternatives
      end

      return spec
    end

    def [](name)
      return @index[name]
    end

    def []=(name, dependency)
      @list << [ dependency ] if @index[name].nil?
      @index[name] = dependency
    end

    def each
      # sort list by name of first alternative
      @list.sort! { |a, b| a[0].name <=> b[0].name }

      # yield each array of alternatives
      @list.each do |alternatives|
        yield alternatives
      end
    end

    def collect(&block)
      @list.collect &block
    end

    def empty?
      @list.empty?
    end

    def unfulfilled_dependencies()
      unfulfilled_spec = DependencySpecification.new

      self.each do |alternatives|
        fulfilled = false

        alternatives.each do |dependency|
          if dependency.fulfilled?
            fulfilled = true
            break
          end
        end

        # save, if not fulfilled
        if not fulfilled
          alternatives.each { |dep| unfulfilled_spec.index[dep.name] = dep }
          unfulfilled_spec.list << alternatives
        end
      end

      return unfulfilled_spec
    end

    def to_s
      return "" if @list.empty?

      @list.collect do |choices|
        choices.collect do |alt|
          case alt.version
            when nil
              "#{alt.name}"
            else
              "#{alt.name} (#{alt.version})"
          end
        end.join(' | ')
      end.join(', ')
    end

  end

end
