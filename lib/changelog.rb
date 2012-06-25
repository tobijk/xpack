# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Generator
# Copyright (C) 2010-2011, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'nokogiri'
require 'time'

class Changelog

  DEBIAN_TRANSFORM = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="text" indent="no" omit-xml-declaration="yes"/>

  <xsl:strip-space elements="
    changelog
    release
    changeset"/>

  <xsl:template match="/changelog">
    <xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="release">
    <!-- section header -->
    <xsl:value-of select="normalize-space(/changelog/@source)"/>
    <xsl:text> (</xsl:text>
    <xsl:value-of select="@version"/>
    <xsl:text>-</xsl:text>
    <xsl:value-of select="@revision"/>
    <xsl:text>) unstable; urgency=low</xsl:text>
    <xsl:text>&#x0a;&#x0a;</xsl:text>

    <!-- section content -->
    <xsl:apply-templates/>
    <xsl:text>&#x0a;</xsl:text>

    <!-- section trailer -->
    <xsl:text> -- </xsl:text>
    <xsl:value-of select="@maintainer"/>
    <xsl:text> &lt;</xsl:text>
    <xsl:value-of select="normalize-space(@email)"/>
    <xsl:text>&gt;  </xsl:text>
    <xsl:value-of select="@date"/>
    <xsl:text>&#x0a;&#x0a;</xsl:text>
  </xsl:template>

  <xsl:template match="comment()">
    <!-- drop comments -->
  </xsl:template>

  <xsl:template match="changeset">
    <xsl:apply-templates/>
    <xsl:if test="following-sibling::changeset">
      <xsl:text>&#x0a;</xsl:text>
    </xsl:if>
  </xsl:template>

  <xsl:template match="li">
    <xsl:text>  * </xsl:text>
    <xsl:value-of select="normalize-space(.)"/>
    <xsl:text>&#x0a;</xsl:text>
  </xsl:template>

  <xsl:template match="*|text()">
  </xsl:text>

</xsl:stylesheet>
EOF

  def initialize(changelog, parms = {})

    case changelog
      when Nokogiri::XML::Element
        @changelog = changelog
      when String
        @changelog = Nokogiri::XML(changelog).root
      else
        raise RuntimeError
    end

    date_node = @changelog.at_xpath("release/@date")
    timestamp = Time.parse(date_node.content)
    date_node.content = timestamp.strftime("%a, %d %b %Y %T %z")
  end

  def format_for_debian()
    doc = Nokogiri::XML::Document.new
    @changelog.dup(1).parent = doc
    stylesheet = Nokogiri::XSLT(DEBIAN_TRANSFORM)
    stylesheet.apply_to(doc)
  end

end
