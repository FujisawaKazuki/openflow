# -*- coding: utf-8 -*-
#
# Simple layer-2 switch with traffic monitoring.
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
require "fdb"
require "../trema/ruby/trema/switch"


class TrafficMonitor < Controller
  #periodic_timer_event :show_counter, 10


  def start
    ##@counter = Counter.new
    @fdb = Hash.new do | hash, datapath_id |
      hash[ datapath_id ] = FDB.new 
    end
    #macアドレス別のパケット集計
    @counter = Hash.new do | hash, datapath_id |
      hash[ datapath_id ] = Counter.new 
    end
    #ipアドレス別のパケット集計
    @counter_ip = Hash.new do | hash, datapath_id |
      hash[ datapath_id ] = Counter.new
    end
    @counter_te = {}
    #スイッチのmacアドレスを格納
    @switches ={}
    @count = 10
  end
  
  def switch_ready datapath_id
    
    
    ##@fdb[ datapath_id ] = FDB.new
    puts "#{datapath_id.to_hex}"
    send_message datapath_id,FeaturesRequest.new
  end

  def features_reply datapath_id,message
    puts ":#{datapath_id}--"
    message.ports.each do |each|
      puts "   mac : #{each.number}-#{each.hw_addr.to_s}"#スイッチのもつポートの番号とmacアドレスを表示
      if each.number.to_s =~ /65534/ then
        @switches[datapath_id] = each.hw_addr #スイッチのmacアドレスを格納
      end
      puts "switch #{@switches[datapath_id]}"
    end
  end

  def packet_in datapath_id, message
    macsa = message.macsa
    macda = message.macda
    if @fdb[datapath_id].nil? then
      @fdb[datapath_id] = FDB.new
      @counter[datapath_id] = Counter.new
      @counter_ip[datapath_id] = Counter.new
    end

      ##fdb = @fdb[datapath_id]

    @fdb[datapath_id].learn macsa.to_s, message.in_port

    #パケットを1カウント
    @counter[datapath_id].add macsa, 1, message.total_len
    @counter_ip[datapath_id].add message.ipv4_saddr.to_s, 1, message.total_len

    
    out_port = @fdb[datapath_id].lookup( macda.to_s )
    #puts "----#{message.in_port.to_s},#{out_port}"

    #スイッチのmacアドレスを取得してから、送信元macを書き換える
    if @switches[datapath_id].nil? then
      if out_port
        packet_out datapath_id, message, out_port
        flow_mod datapath_id, macsa, macda, out_port
      else
        flood datapath_id, message
      end
    else
      if out_port
        packet_out2 datapath_id, message, out_port
        flow_mod2 datapath_id, macsa, macda, out_port
      else
        flood2 datapath_id, message
      end
    end       
  end


  def flow_removed datapath_id, message
    number = message.priority

    @counter[datapath_id].add message.match.dl_src.to_s, message.packet_count, message.byte_count
    @counter_ip[datapath_id].add message.match.nw_src.to_s, message.packet_count, message.byte_count
    @count = @count -1
    if @count == 0 then
      i = 1
      while i < 6
        set_path i
        i += 1
      end
      i = 1
      while i < 6
        @counter_te[i] ||= { :packet_count => 0}
        i += 1
      end
    end
    if @count < 0 then
      set_path number
      puts "#{number}"

      if message.packet_count > 0 then
=begin
        puts "phase set_path now"
        puts "--set--#{datapath_id.to_hex} No.#{message.priority}--#{message.packet_count}packets from #{ message.match.dl_src.to_s} "
        puts "       because #{message.duration_sec} passed /#{@count}"
=end           
        @counter_te[datapath_id][ :packet_count ] += message.packet_count if /655/ !~ message.priority.to_s
        puts "switch #{datapath_id.to_hex} #{@counter_te[datapath_id][:packet_count]} packets"
      end   
    end
     
  end
  


  ##############################################################################
  private
  ##############################################################################


  def show_counter
    puts Time.now
#    @counter.each_pair do | datapath_id, counter|
#      puts "sw#{datapath_id} "
#      counter.each_pair do | mac, counter |
#        if /00:00:*/ =~ mac.to_s then
#          puts "  MAC:#{ mac } #{ counter[ :packet_count ] } packets (#{ counter[ :byte_count ] } bytes)"
#        end
#      end
#    end
    
    @counter_ip.each_pair do | datapath_id, counter|
     puts "sw#{datapath_id} "
      counter.each_pair do | mac, counter |
        if /192.168.0/ =~ mac.to_s then
           puts "  IP:#{ mac } #{ counter[ :packet_count ] } packets (#{ counter[ :byte_count ] } bytes)"
          end
      end
    end
  end


  def flow_mod datapath_id,macsa, macda, out_port
    send_flow_mod_add(
      datapath_id,
      :hard_timeout => 5,
      :match => Match.new( :dl_src => macsa, :dl_dst => macda ),
      :action => ActionOutput.new( out_port)
      #:actions => [SetEthSrcAddr.new(@switches[datapath_id]),
      #             ActionOutput.new( out_port )]
    )

  end


  def packet_out datapath_id, message, out_port
    send_packet_out(
      datapath_id,
      :packet_in => message,
      :action => ActionOutput.new( out_port)
      #:actions => [SetEthSrcAddr.new(@switches[datapath_id]),
      #             ActionOutput.new( out_port )]
    )
    if /65/ !~ out_port.to_s then
      puts "packet_out #{datapath_id.to_hex} to  #{out_port}" 
    end
  end

  def flood datapath_id, message
    packet_out datapath_id, message, OFPP_FLOOD
  end



  #2がついてるメソッドが送信元macアドレスを書き換える
  def flow_mod2 datapath_id,macsa, macda, out_port
    send_flow_mod_add(
      datapath_id,
      :hard_timeout => 5,
      :match => Match.new( :dl_src => macsa, :dl_dst => macda ),
      #:action => ActionOutput.new( out_port)
      :actions => [SetEthSrcAddr.new(@switches[datapath_id]),
                   ActionOutput.new( out_port )]
    )
    puts "flow_mod2 #{datapath_id.to_hex} to  #{out_port}-#{macda}" 
  end


  def packet_out2 datapath_id, message, out_port
    send_packet_out(
      datapath_id,
      :packet_in => message,
      #:action => ActionOutput.new( out_port)
      :actions => [SetEthSrcAddr.new(@switches[datapath_id]),
                   ActionOutput.new( out_port )]
    )
    if /65/ !~ out_port.to_s then
      puts "packet_out2 #{datapath_id.to_hex} to  #{out_port}" 
    end

  end


  def flood2 datapath_id, message
    packet_out2 datapath_id, message, OFPP_FLOOD
    puts "flood2 #{datapath_id.to_hex}" 
  end


  def set_path set_id

    

    ht = 20
    out_port4 = @fdb[3].lookup @switches[5].to_s
    out_port5 = @fdb[5].lookup @switches[4].to_s
    out_port6 = @fdb[4].lookup @switches[1].to_s

    out_port8 = @fdb[3].lookup @switches[2].to_s
    


    
    # puts "set port #{out_port},#{@switches[3]}"
    case set_id
    when 1
      out_port1 = @fdb[1].lookup @switches[4].to_s
      send_flow_mod_add(
                        0x1,
                        :hard_timeout => ht,
                        :cookie => 1,
                        :priority => 1,
                        #:match => Match.new(:nw_src => "192.168.0.1"),
                        :actions => [SetEthSrcAddr.new(@switches[1]),
                                     SendOutPort.new( out_port1 )]
                        )
      #puts "mod^1"
    when 2
      out_port2 = @fdb[4].lookup @switches[5].to_s
      send_flow_mod_add(
                        0x4,
                        :hard_timeout => ht,
                        :cookie => 2,
                        :priority => 2,
                        #:match => Match.new(:nw_src => "192.168.0.1"),
                        :actions => [SetEthSrcAddr.new(@switches[4]),
                                     ActionOutput.new( out_port2 )]
                        )
      #puts "mod^2"
    when 3
      out_port3 = @fdb[5].lookup @switches[3].to_s
      send_flow_mod_add(
                        0x5,
                        :hard_timeout => ht,
                        :priority => 3,
                        #:match => Match.new(:nw_src => "192.168.0.1"),
                        :actions => [SetEthSrcAddr.new(@switches[5]),
                                     ActionOutput.new( out_port3 )]
                        )
      #puts "mod^3"
    when 4
      out_port7 = @fdb[2].lookup @switches[3].to_s
      send_flow_mod_add(
                        0x2,
                        :hard_timeout => ht,
                        :priority => 4,
                        #:match => Match.new(:nw_src => "192.168.0.2"),
                        :actions => [SetEthSrcAddr.new(@switches[2]),
                   ActionOutput.new( out_port7 )]
                        )
      #puts "mod^8"
    when 5
      out_port9 = @fdb[3].lookup "00:00:00:00:00:03"
      send_flow_mod_add(
                        0x3,
                        :hard_timeout => ht,
                        :cookie => 0x10,
                        :priority => 5,
                        #:match => Match.new(:nw_src => "192.168.0.1"),
                        :actions => [SetEthSrcAddr.new(@switches[3]),
                                     ActionOutput.new( out_port9 )]
                        )
      #puts "mod^9"
  
    end
  end
  
  
end


### Local variables:
### mode: Ruby
### coding: utf-8
### indent-tabs-mode: nil
### End:
