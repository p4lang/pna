/*
Copyright 2021 Intel Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#include <core.p4>
#include "../pna.p4"


// Very simple PNA program intended only to demonstrate how to send
// unicast packets to a destination network port, or host vport, based
// upon the destination MAC address in the Ethernet header.


typedef bit<48>  EthernetAddress;
typedef bit<32>  IPv4Address;

header ethernet_t {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLength;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    IPv4Address srcAddr;
    IPv4Address dstAddr;
}

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<4>  res;
    bit<8>  flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

bool TCP_FIN_flag_set(in bit<8> flags) {
    return (flags[0:0] == 1);
}

bool TCP_SYN_flag_set(in bit<8> flags) {
    return (flags[1:1] == 1);
}

bool TCP_RST_flag_set(in bit<8> flags) {
    return (flags[2:2] == 1);
}

bool TCP_ACK_flag_set(in bit<8> flags) {
    return (flags[4:4] == 1);
}

// Define names for different expire time profile id values.

const ExpireTimeProfileId_t EXPIRE_TIME_PROFILE_NOW    = (ExpireTimeProfileId_t) 0;
const ExpireTimeProfileId_t EXPIRE_TIME_PROFILE_MEDIUM = (ExpireTimeProfileId_t) 1;
const ExpireTimeProfileId_t EXPIRE_TIME_PROFILE_LONG   = (ExpireTimeProfileId_t) 2;
const ExpireTimeProfileId_t EXPIRE_TIME_PROFILE_NEVER  = (ExpireTimeProfileId_t) 3;

//////////////////////////////////////////////////////////////////////
// Struct types for holding user-defined collections of headers and
// metadata in the P4 developer's program.
//////////////////////////////////////////////////////////////////////

struct metadata_t {
}

struct headers_t {
    ethernet_t eth;
    ipv4_t     ipv4;
    tcp_t      tcp;
}

parser MainParserImpl(
    packet_in pkt,
    out   headers_t  hdr,
    inout metadata_t meta,
    in    pna_main_parser_input_metadata_t istd)
{
    state start {
        pkt.extract(hdr.eth);
        transition select (hdr.eth.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select (hdr.ipv4.protocol) {
            6: parse_tcp;
            default: accept;
        }
    }
    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
    }
}

control PreControlImpl(
    in    headers_t  hdr,
    inout metadata_t meta,
    in    pna_pre_input_metadata_t  istd,
    inout pna_pre_output_metadata_t ostd)
{
    apply {
        // No IPsec decryption for this example program, so pre
        // control does nothing.
    }
}

struct ct_tcp_table_hit_params_t {
    FlowId_t flow_id;
}

control MainControlImpl(
    inout headers_t  hdr,
    inout metadata_t meta,
    in    pna_main_input_metadata_t  istd,
    inout pna_main_output_metadata_t ostd)
{
    action drop () {
        drop_packet();
    }

    // Inputs from previous tables (or actions, or in general other P4
    // code) that can modify the behavior of actions of ct_tcp_table.
    bool do_add_on_miss;
    bool update_expire_time;
    ExpireTimeProfileId_t new_expire_time;

    // Outputs from actions of ct_tcp_table
    FlowId_t my_flow_id;
    bool add_succeeded;
    
    
    action ct_tcp_table_hit (FlowId_t flow_id) {
        my_flow_id = flow_id;
        if (update_expire_time) {
            set_entry_expire_time(new_expire_time);
            restart_expire_timer();
        } else {
            restart_expire_timer();
        }
        // a target might also support additional statements here
    }

    action ct_tcp_table_miss() {
        if (do_add_on_miss) {
            my_flow_id = allocate_flow_id();
            add_succeeded =
                add_entry(action_name = "ct_tcp_table_hit",  // name of action
                          action_params = (ct_tcp_table_hit_params_t)
                                          {flow_id = my_flow_id});
        }
        // a target might also support additional statements here, e.g.
        // mirror the packet
        // update a counter
        // set receive queue
    }

    table ct_tcp_table {
        /* add_on_miss table is restricted to have all exact match fields */
        key = {
            // other key fields also possible, e.g. VRF

            // alternate if istd.direction were a bool
            istd.direction ? hdr.ipv4.srcAddr : hdr.ipv4.dstAddr:
                exact @name("ipv4_addr_0");

            SelectByDirection(istd.direction, hdr.ipv4.srcAddr, hdr.ipv4.dstAddr):
                exact @name("ipv4_addr_0");
            SelectByDirection(istd.direction, hdr.ipv4.dstAddr, hdr.ipv4.srcAddr):
                exact @name("ipv4_addr_1");
            hdr.ipv4.protocol : exact;
            SelectByDirection(istd.direction, hdr.tcp.srcPort, hdr.tcp.dstPort):
                exact @name("tcp_port_0");
            SelectByDirection(istd.direction, hdr.tcp.dstPort, hdr.tcp.srcPort):
                exact @name("tcp_port_1");
        }
        actions = {
            @tableonly   ct_tcp_table_hit;
            @defaultonly ct_tcp_table_miss;
        }

        // New PNA table property 'add_on_miss = true' indicates that
        // this table can use extern function add_entry() in its
        // default (i.e. miss) action to add a new entry to the table
        // from the data plane.
        add_on_miss = true;

        // New PNA table property 'idle_timeout_with_auto_delete' is
        // similar to 'idle_timeout' in other architectures, except
        // that entries that have not been matched for their expire
        // time interval will be deleted, without the control plane
        // having to delete the entry.
        idle_timeout_with_auto_delete = true;
        const default_action = ct_tcp_table_miss;
    }

    apply {
        // The following code is here to give an _example_ similar to
        // the desired behavior, but is likely to be implemented in a
        // variety of ways, e.g. one or more P4 table lookups.  It is
        // also likely NOT to be identical to what someone experienced
        // at writing TCP connection tracking code actually wants.

        // The important point is that all of these variables:

        // + do_add_on_miss
        // + update_expire_time
        // + new_expire_time

        // are assigned the values we want them to have _before_
        // calling ct_tcp_table.apply() below.  The conditions under
        // which they are assigned different values depends upon the
        // contents of the packet header fields and the direction of
        // the packet, and perhaps some earlier P4 table entries
        // populated by control plane software, but _not_ upon the
        // current entries installed in the ct_tcp_table.

        do_add_on_miss = false;
        update_expire_time = false;
        if (hdr.ipv4.isValid() && hdr.tcp.isValid()) {
            if (istd.direction == PNA_Direction_t.HOST_TO_NET) {
                if (TCP_SYN_flag_set(hdr.tcp.flags)) {
                    do_add_on_miss = true;
                    update_expire_time = true;
                    new_expire_time = EXPIRE_TIME_PROFILE_LONG;
                } else if (TCP_FIN_flag_set(hdr.tcp.flags) ||
                           TCP_RST_flag_set(hdr.tcp.flags))
                {
                    update_expire_time = true;
                    new_expire_time = EXPIRE_TIME_PROFILE_NOW;
                } else {
                    update_expire_time = true;
                    new_expire_time = EXPIRE_TIME_PROFILE_MEDIUM;
                }
            }
        }

        // ct_tcp_table is a bidirectional table
        if (hdr.ipv4.isValid() && hdr.tcp.isValid()) {
            if (ct_tcp_table.apply().hit) {
                // do not drop the packet
                if (do_add_on_miss) {
                    // Code here to send mirror packet to control plane
                    // software with some kind of header or error status
                    // indicating that an attempted add_on_miss failed.
                }
            }
        }
    }
}

control MainDeparserImpl(
    packet_out pkt,
    in    headers_t hdr,
    in    metadata_t meta,
    in    pna_main_output_metadata_t ostd)
{
    apply {
        pkt.emit(hdr.eth);
    }
}

PNA_NIC(
    PreControlImpl(),
    MainParserImpl(),
    MainControlImpl(),
    MainDeparserImpl(),
    // The last arg is optional, but leaving it here for the moment
    MainParserImpl()) main;
