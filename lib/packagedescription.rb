# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Generator
# Copyright (C) 2010-2011, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

class PackageDescription

  INLINE_ELEMENTS_STYLE = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:template match="em">
    <xsl:text>|</xsl:text><xsl:apply-templates/><xsl:text>|</xsl:text>
  </xsl:template>

  <xsl:template match="*|text()|comment()">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:apply-templates/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>
EOF

  BLOCK_ELEMENTS_STYLE = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xpack="http://www.nonterra.com/2011/XSL/XPack"
  extension-element-prefixes="xpack">

  <xsl:output method="text" omit-xml-declaration="yes" encoding="UTF-8"/>

  <xsl:template match="description">
      <xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="p">
    <xsl:value-of select="xpack:block_format(.)"/>
    <xsl:if test="following-sibling::*">
      <xsl:text>&#x0a; .&#x0a;</xsl:text>
    </xsl:if>
  </xsl:template>

  <xsl:template match="ul">
    <xsl:apply-templates/>
    <xsl:if test="following-sibling::*">
      <xsl:text>&#x0a; .&#x0a;</xsl:text>
    </xsl:if>
  </xsl:template>

  <xsl:template match="li">
    <xsl:value-of select="xpack:block_format(.)"/>
    <xsl:if test="following-sibling::*">
      <xsl:text>&#x0a;</xsl:text>
    </xsl:if>
  </xsl:template>

  <xsl:template match="node()|comment()"/>

</xsl:stylesheet>
EOF

  def initialize(xml_input)
    case xml_input
      when Nokogiri::XML::Element
        @desc_node = xml_input
      when String
        @desc_node = Nokogiri::XML(xml_input).root
      else
        raise RuntimeError
    end
  end

  def summary
    summary_text = @desc_node.at_xpath('summary').content.strip
    return normalize_space(summary_text)
  end

  def full_description
    doc0 = Nokogiri::XML::Document.new
    @desc_node.dup(1).parent = doc0

    inline_elements_style = Nokogiri::XSLT(INLINE_ELEMENTS_STYLE)
    doc1 = inline_elements_style.transform(doc0)
    block_elements_style = \
      Nokogiri::XSLT(
        BLOCK_ELEMENTS_STYLE,
        { 'http://www.nonterra.com/2011/XSL/XPack' =>
          PackageDescription::CustomXPath }
      )
    doc2 = block_elements_style.transform(doc1)

    return doc2.content
  end

  def normalize_space(text)
    return text.gsub(/\s+/, ' ').strip
  end

  class CustomXPath

    def block_format(node, arg2 = '')
      width = 80
      indent = case node[0].name
        when 'li'
          3
        when 'p'
          1
      end

      lines = []
      line = ' ' * indent

      text = node[0].content.strip
      text.scan(/\S+/) do |match|
        if line.size + match.size > width
          unless line.strip.empty?
            lines << line
            line = ' ' * indent
          end
        end
        line += match
        line += ' ' unless line.size >= width
      end
      lines << line unless line.strip.empty?

      result = lines.join("\n")
      result[1] = '*' if node[0].name == 'li'
      return result
    end

  end

end

