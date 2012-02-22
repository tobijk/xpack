#!/usr/bin/env ruby

require 'erb'

def esc(string)
  string\
    .gsub(/&/, '&amp;')\
    .gsub(/</, '&lt;')\
    .gsub(/>/, '&gt;')\
    .gsub(/"/, '&quot;')
end

ERB_SOURCE_PACKAGE = ERB.new(<<'EOF')
<%
      source   = @control.source
      packages = @control.packages

%><?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE control [<%
packages.each do |pkg| %>
  <!ENTITY <%= pkg['name'] %> SYSTEM "<%= pkg['name'] %>.xml"><%
end %>
  <!ENTITY rules SYSTEM "rules.xml">
  <!ENTITY changelog SYSTEM "changelog.xml">
]>
<control xmlns:xi="http://www.w3.org/2001/XInclude">

    <defines>
        <def name="XPACK_SOURCE_DIR"  value="<%= source['name'] + '-src'%>"/>
        <def name="XPACK_BUILD_DIR"   value="tmp-build"/>
        <def name="XPACK_INSTALL_DIR" value="tmp-install"/>
    </defines>

    <source name="<%= source['name'] %>" architecture-independent="<%= @control.arch_indep? %>">
        <description>
            <summary><%= packages[0]['summary'] %></summary>
            <p>
<%= packages[0]['description'].gsub(/^/m, " " * 11) %>
            </p>
        </description>

        <sources>
            <file src="<%= source['name'] + '-' + @changelog[0].upstream_version + '.tar.bz2' %>"/>
        </sources>

        <requires><%
            source['build-depends'].each do |pkg, version|
              if version
                %>
            <package name="<%= pkg %>" version="<%= esc(version) %>"/><%
              else
                %>
            <package name="<%= pkg %>"/><%
              end
            end %>
        </requires>

        <!-- build rules -->
        &rules;
    </source>

    <!-- package rules --><%
    @control.each_package do |pkg| %>
    <%= '&' + pkg['name'] + ";" %><%
    end %>

    <!-- changelog -->
    &changelog;

</control> 
EOF

ERB_PACKAGE_RULES = ERB.new(<<'EOF')
<?xml version="1.0" encoding="utf-8"?>
<rules>

    <prepare>
    <![CDATA[

cd $XPACK_BUILD_DIR
$XPACK_SOURCE_DIR/configure \
    --prefix=/usr \
    --disable-nls

    ]]>
    </prepare>

    <build>
    <![CDATA[

cd $XPACK_BUILD_DIR
make -j$XPACK_PARALLEL_JOBS

    ]]>
    </build>

    <install>
    <![CDATA[

cd $XPACK_BUILD_DIR
make DESTDIR=$XPACK_INSTALL_DIR install

    ]]>
    </install>

    <clean>
    <![CDATA[

rm -fr "$XPACK_SOURCE_DIR" "$XPACK_BUILD_DIR" "$XPACK_INSTALL_DIR"

    ]]>
    </clean>

</rules>
EOF

ERB_BINARY_PACKAGE = ERB.new(<<'EOF')
<?xml version="1.0" encoding="utf-8"?>
<package name="<%= package['name'] %>" section="<%= package['section'] %>">
    <description>
        <summary><%= package['summary'] %></summary>
        <p>
<%= package['description'].gsub(/^/m, " " * 7) %>
        </p>
    </description>

    <requires><%
        package['depends'].each do |pkg, version|
          if version
            %>
        <package name="<%= pkg %>" version="<%= esc(version) %>"/><%
          else
            %>
        <package name="<%= pkg %>"/><%
          end
        end %>
    </requires>

    <contents><%
      package['files'].each { |f| %>
        <file src="<%= f %>"/><% } if package['files'] %><%
      package['dirs'].each { |d| %>
        <dir src="<%= d %>"/><% } if package['dirs'] %>
    </contents>
</package>
EOF

ERB_CHANGELOG = ERB.new(<<'EOF')
<?xml version="1.0" encoding="utf-8"?>
<changelog>
    <release version="<%= @changelog[0].upstream_version %>" revision="1" maintainer="<%= @changelog[0].maintainer %>"
     email="<%= @changelog[0].email %>" date="<%= Time.now.strftime('%Y-%m-%d %H:%M:%S %Z') %>">
        <changeset>
            <li>Initial packaging</li>
        </changeset>
    </release>
</changelog>
EOF

module Debian

  class Changelog

    class Entry
      attr_reader :version, :content, :maintainer, :email, :date

      def initialize(version, content, maintainer, email, date)
        @version    = version
        @content    = content
        @maintainer = maintainer
        @email      = email
        @date       = date
      end

      def upstream_version
        @version\
          .match(/^(?:(\d+):)?([-.+~a-zA-Z0-9]+?)(?:-([.~+a-zA-Z0-9]+)){0,1}$/)[2]
      end

    end

    class << self

      def load(filename)
        entries = Array.new

        version = nil
        content = ""
        email   = ""
        date    = Time.now

        File.open(filename, 'r') do |f|
          f.each_line do |line|
            if line.match(/^[-.a-z0-9]+\s+\(([^)]+)\)\s+[-a-z0-9]+;\s*urgency=\w+/)
              version = $1
              content = ""
            elsif line.match(/ --\s+([^<]+)\s+<([^>]+)>\s+((?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), .*)/)
              maintainer = $1
              email = $2
              date  = $3
              entries << Entry.new(version, content, maintainer, email, date)
            else
              content += line
            end
          end
        end

        Changelog.send(:new, entries)
      end

    end

    def [](index)
      @entries[index]
    end

    private

    def initialize(entries)
      @entries = entries
    end

  end


  class Control
    attr_reader :source, :packages

    class << self

      def load(filename)
        content = File.open(filename, 'r') { |f| f.read }

        field_name = field_content = nil

        entries = content.split(/(?:\r|(?:\r)?\n){2,}/).map do |entry|
          fields = {}

          entry.each_line do |line|
            next if line.start_with? '#'

            if line.match(/^\S+:/)
              field_name, field_content = line.split(':', 2)

              field_name.downcase!
              fields[field_name] = field_content

              fields['name'] = field_content \
                if [ 'source', 'package' ].include?(field_name)
            elsif line.match(/^\s+\S/)
              fields[field_name] += line
            end
          end

          fields.each_key do |k|
            fields[k].strip!
          end
        end

        # those entries were commented out
        entries.delete({})

        # throw out udebs and dbg packages
        entries.delete_if { |e|
          e['section'].to_s =~ /^\s*debian-installer\s*$/ ||\
          e['package'].to_s =~ /-(?:udeb|dbg)$/ ||\
          e['xc-package-type'].to_s == 'udeb'
        }

        entries.each do |e|
          [ 'depends', 'build-depends' ].each do |dep_type|
            unless e[dep_type].nil?
              e[dep_type] = \
                e[dep_type]\
                  .gsub(/\s+/, '')\
                  .gsub(/\[[^\]]+\]/, '')\
                  .gsub(/(\([<=>]+)/, '\1 ')\
                  .gsub(/= \$\{binary:Version\}/, '==')\
                  .split(',')\
                  .delete_if { |dep| dep.match(/\$\{(?:shlibs|misc):(?:Depends|Suggests)\}/) }\
                  .map { |dep| dep.match(/([^(]+)(?:\(([^)]+)\))?/)[1,2] }
            else
              e[dep_type] = []
            end
          end

          unless e['description'].nil?
            summary, description = e['description'].split("\n", 2)
            summary, description = esc(summary), esc(description)
            description.gsub!(/^(\s+)\.\s*$/, "\\1</p>\n\\1<p>")
            e['summary'], e['description'] = summary, description
          end

          unless e['source']
            e['files'], e['dirs'] = \
              Auxiliary.load_content_spec(e['name'], File.dirname(filename))
          end
        end

        Control.send('new', entries.shift, entries)
      end

    end

    def each_package
      @packages.each do |pkg|
        yield pkg
      end
    end

    def arch_indep?
      @arch_indep
    end

    private

    def initialize(source, packages)
      @source = source
      @packages = packages
      @arch_indep = @packages.select { |p| p['architecture'] != 'all' }.empty?
    end

    private_class_method :new
  end


  class Auxiliary

    class << self

      def load_content_spec(package_name, path)
        filter = [
          'files',
          'install',
          'dirs',
          "#{package_name}.files",
          "#{package_name}.install",
          "#{package_name}.dirs"
        ].map { |f| File.join(path, f) }

        content = Hash.new { |h, k| h[k] = [] }

        Dir.glob(filter).each do |file|
          name = type = nil
          basename = File.basename(file)

          type = unless [ 'files', 'install', 'dirs' ].include? basename
            basename.match(/\.([^.]+)$/)[1]
          else
            file
          end

          content[type] = File.open(file, 'r').read\
            .split(/$/)\
            .map {|e| e.strip}\
            .delete_if {|e| e.empty? }
        end

        files = (content['files'] + content['install'])
        files.uniq!
        files.map! { |f| '/' + f unless f =~ /^\// }

        dirs = content['dirs']
        dirs.map!  { |d| '/' + d unless d =~ /^\// }

        return files, dirs
      end

    end

    private_class_method :new
  end


  class PackageInfo

    def self.load(path = '.')
      control = Control.load(path + '/control')
      changelog = Changelog.load(path + '/changelog')
      PackageInfo.send(:new, control, changelog)
    end

    def write_xml(outpath = '.')
      write_xml_source_package(outpath)
      write_xml_binary_package(outpath)
      write_xml_package_rules(outpath)
      write_xml_changelog(outpath)
    end

    private

    def initialize(control, changelog = nil, files = nil, dirs = nil)
      @control = control
      @changelog = changelog
      @files = files
      @dirs = dirs
    end

    def write_xml_source_package(outpath)
      File.open(outpath + '/package.xml', 'wb+') do |f|
        f.write ERB_SOURCE_PACKAGE.result(binding)
      end
    end

    def write_xml_binary_package(outpath)
      @control.each_package do |package|
        File.open(outpath + '/' + package['name'] + '.xml', 'wb+') do |f|
          f.write ERB_BINARY_PACKAGE.result(binding)
        end
      end
    end

    def write_xml_package_rules(outpath)
      File.open(outpath + '/rules.xml', 'wb+') do |f|
        f.write ERB_PACKAGE_RULES.result(binding)
      end
    end

    def write_xml_changelog(outpath)
      File.open(outpath + '/changelog.xml', 'wb+') do |f|
        f.write ERB_CHANGELOG.result(binding)
      end
    end

    private_class_method :new
  end

end

begin #main()
  pkg_info = Debian::PackageInfo.load(ARGV[0])
  pkg_info.write_xml()
end
