#
# Forwarding database (FDB) of layer-2 switch.
#
# Copyright (C) 2008-2013 NEC Corporation
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#


require "counter"

class FDB
  def initialize 
    @db = {}
  end

  def get_size
    return @db.size
  end

  def lookup mac
    #puts "^^^^^^^#{@db[mac].to_s}"
    return @db[ mac ]
  end

  def lookup_port mac
    ##@db[mac][:port_number]
  end


  def learn mac, port_number
    ##@db[ mac ] ||= { :port_number => 0}
    ##@db[ mac ][ :port_number ] = port_number
    @db[ mac ] = port_number
  end


  def each_pair &block
    @db.each_pair &block
  end

end


### Local variables:
### mode: Ruby
### coding: utf-8
### indent-tabs-mode: nil
### End:
