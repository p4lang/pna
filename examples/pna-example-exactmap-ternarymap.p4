/*
Copyright 2022 Intel Corporation

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

header ethernet_t {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
}

//////////////////////////////////////////////////////////////////////
// Struct types for holding user-defined collections of headers and
// metadata in the P4 developer's program.
//////////////////////////////////////////////////////////////////////

struct metadata_t {
}

struct headers_t {
    ethernet_t eth;
}

struct emap1_key {
    bit<8> my_field;
}

struct emap2_key {
    bit<8> my_field;
}

struct emap2_val {
    bit<4>  val1;
    bit<12> val2;
}

struct tmap1_key {
    bit<24> f1;
    bit<3> f2;
}

struct tmap2_key {
    bit<18> only_field;
}

struct tmap2_val {
    bit<8>  v1;
    bit<10> v2;
}

parser MainParserImpl(
    packet_in pkt,
    out   headers_t  hdr,
    inout metadata_t meta,
    in    pna_main_parser_input_metadata_t istd)
{
    state start {
        pkt.extract(hdr.eth);
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

control MainControlImpl(
    inout headers_t  hdr,
    inout metadata_t meta,
    in    pna_main_input_metadata_t  istd,
    inout pna_main_output_metadata_t ostd)
{

    // Example instantiation from documentation comments for ExactMap
    // extern in pna.p4
    ExactMap<emap1_key, bit<16>>(
        size = 1024,
        const_entries = (list<exactmap_const_entry_t<emap1_key, bit<16>>>) {
            {{ 5}, 10},  // key my_field= 5, value 10
            {{ 6}, 27},  // key my_field= 6, value 27
            {{10},  2}   // key my_field=10, value  2
        },
        default_value = 42)  // default value returned for all other keys
    emap1;

    ExactMap<emap2_key, emap2_val>(
        size = 128,
        initial_entries = (list<exactmap_initial_entry_t<emap2_key, emap2_val>>) {
            // not const entry, key my_field=5, value {val1=10, val2=4}
            {false, { 5}, {val1=10, val2=   4}},
            // const entry, key my_field=6, value {val1=15, val2=4095}
            { true, { 6}, {val1=15, val2=4095}},
            // const entry, key my_field=10, value {val1=0, val2=28}
            { true, {10}, {val1= 0, val2=  28}}
        },
        // default value returned for all other keys
        default_value = {val1=9, val2=42})
    emap2;

    TernaryMap<tmap1_key, bit<16>>(
        size = 1024,
        const_entries = (list<ternarymap_const_entry_t<tmap1_key, bit<16>>>) {
            // ternary key with
            // + value 5, mask 0xffffff (exact match on least
            //   significant 24 bits) for field f1,
            // + value 2, mask 0x7 (exact match on all 3 bits)
            //   for field f2,
            // and value 10:
            {{       5,   2},
             {0xffffff, 0x7},
             10},

            // ternary key with
            // + value 6, mask 0xff00ff (wildcard on middle 8
            //   bits, exact match on the rest) for field f1,
            // + value 2, mask 0x7 (exact match on all 3 bits)
            //   for field f2,
            // and value 27:
            {{       6,   2},
             {0xff00ff, 0x7},
             27},
            
            // ternary key with
            // + value 10, mask 0x00ffff (exact match on least
            //   significant 16 bits, wildcard on bits
            //   [23:16]),
            // + value 0, mask 0x2 (exact match on only the
            //   middle bit) for field f2,
            // and value 2:
            {{      10,   0},
             {0x00ffff, 0x2},
             2}
        },
        default_value = 42)  // default value returned for all other keys
    tmap1;

    TernaryMap<tmap2_key, tmap2_val>(
        size = 1024,
        largest_priority_wins = true,
        initial_entries =
            (list<ternarymap_initial_entry_t<tmap2_key, tmap2_val>>) {
            // const entry (true), priority 100
            // ternary key with value 5, mask 0x3ffff (exact match on least
            //   significant 18 bits) for field only_field,
            // and value {v1=255, v2=1023}
            {true, 100, {5}, {0x3ffff}, {v1=255, v2=1023}},

            // not const entry (false), priority 90
            // ternary key with value 6, mask 0x300ff (wildcard on
            //   bits [15:8], exact match on the rest) for field
            //   only_field,
            // and value {v1=1, v2=18}
            {false,  90, {7}, {0x300ff}, {v1=1, v2=18}},
            
            // const entry (true), priority 1
            // ternary key with value 10, mask 0x0ffff (exact match on
            //   least significant 16 bits, wildcard on bits [17:16]),
            // and value {v1=2, v2=23}
            {true,    1, {10}, {0x0ffff}, {v1=2, v2=23}}
        },
        // default value returned on lookup miss
        default_value = {v1=42, v2=42})
    tmap2;

    action drop () {
        drop_packet();
    }
    action L2_send_to_port (PortId_t port_id) {
        send_to_port(port_id);
    }
    table L2_fwd {
        key = { hdr.eth.dstAddr: exact; }
        actions = { L2_send_to_port; drop; }
        default_action = drop;
    }
    apply {
        // Note that table L2_fwd is one table accessed by packets
        // being processed in both the NET_TO_HOST and the HOST_TO_NET
        // directions.

        // As far as the control plane API is concerned, there is
        // exactly one table.
        L2_fwd.apply();

        // Detail for implementers: Because this particular table has
        // state that is only modified by the control plane API, not
        // the data plane (e.g. it has no direct counters, direct
        // meters, or idle timeout behavior), a compiler is free to
        // implement this by creating two physical tables, as long as
        // the driver software hides this fact from the control plane
        // API.  That is, control software should always be able to
        // perform add, modify, or delete operations on one table, and
        // driver software is responsible for ensuring that all
        // physical state in the target device is updated so that it
        // appears that the one logical table has been updated.
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
    MainParserImpl(),
    PreControlImpl(),
    MainControlImpl(),
    MainDeparserImpl()
    // Hoping to make this optional parameter later, but not supported
    // by p4c yet.
    //, PreParserImpl()
    ) main;
