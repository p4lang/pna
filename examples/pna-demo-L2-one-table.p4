/*
Copyright 2020 Intel Corporation

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
