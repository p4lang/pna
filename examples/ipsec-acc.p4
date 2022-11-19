/*
Copyright 2022 Advanced Micro Devices, Inc

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

/// p4test --Wdisable='unused' --excludeMidendPasses Predication ./ipsec-acc.p4 2>&1 | tee make.out

/// IPSec tunnel mode example using crypto-accelerator extern object
#include <core.p4>
#include "../pna.p4"
#include "./include/crypto-accelerator.p4"

// Helper Externs (could not find it in pna spec/existign code)
// Vendor specific implementation to cause a packet to get recirculated
extern void recirc_packet();

/// Headers

#define ETHERTYPE_IPV4  0x0800

#define IP_PROTO_TCP    0x06
#define IP_PROTO_UDP    0x11
#define IP_PROTO_ESP    0x50

typedef bit<48>  EthernetAddress;

header ethernet_h {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
}

header ipv4_h {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

header tcp_h {
    bit<16>    srcPort;
    bit<16>    dstPort;
    bit<32>    seqNo;
    bit<32>    ackNo;
    bit<4>     dataOffset;
    bit<4>     res;
    bit<8>     flags;
    bit<16>    window;
    bit<16>    checksum;
    bit<16>    urgentPtr;
}

header udp_h {
    bit<16>    srcPort;
    bit<16>    dstPort;
    bit<16>    len;
    bit<16>    checksum;
}

header esp_h {
    bit<32>     spi;
    bit<32>     seq;
}

// rfc4106 esp IV header on the wire
header esp_iv_h {
    bit<64>     iv; // IV on the wire excludes the salt
}
#define IPSEC_OP_NONE       0
#define IPSEC_OP_ENCRYPT    1
#define IPSEC_OP_DECRYPT    2

// Program defined header used during recirculation
header recirc_header_h {
    bit<2>   ipsec_op;
    bit<6>   pad;
    bit<16>  ipsec_len;
}

// User-defined struct containing all of those headers parsed in the
// main parser.
struct headers_t {
    recirc_header_h recirc_header;
    ethernet_h ethernet;
    ipv4_h ipv4_1;
    udp_h udp;
    tcp_h tcp;
    esp_h esp;
    esp_iv_h esp_iv;

    // inner layer - ipsec in tunnel mode
    ipv4_h ipv4_2;
}

/// Metadata

struct main_metadata_t {
    bit<32> sa_index;
    bit<1> ipsec_decrypt_done;
}

/// Instantiate crypto accelerator for AES-GCM algorithm
crypto_accelerator(crypto_algorithm_e.AES_GCM) ipsec_acc;

parser MainParserImpl(
    packet_in pkt,
    out   headers_t       hdr,
    inout main_metadata_t main_meta,
    in    pna_main_parser_input_metadata_t istd)
{
    bit<1> is_recirc = 0;
    bit<2>  ipsec_op = 0;

    state start {
        main_meta.sa_index = 1; // just for exmaple, used for encrypt

        // TODO: can't find  better indication of recirc in the existing pna.p4
        // This should be a field in istd or and extern
        transition select(istd.loopedback) {
            true : parse_recirc_header;
            default : parse_packet;
        }
    }

    state parse_recirc_header {
        pkt.extract(hdr.recirc_header);
        is_recirc = 1;
        ipsec_op = hdr.recirc_header.ipsec_op;
        transition parse_packet;
    }

    state parse_packet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            ETHERTYPE_IPV4 : parse_ipv4;
            default : accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4_1);
        transition select(hdr.ipv4_1.protocol) {
            IP_PROTO_TCP        : parse_tcp;
            IP_PROTO_UDP        : parse_udp;
            IP_PROTO_ESP        : parse_crypto;
            default             : accept;
        }
    }

    state parse_crypto {
        transition select(is_recirc, ipsec_op) {
            // ESP header is present after decrypt operation
            (0x1 &&& 0x1, IPSEC_OP_DECRYPT &&& 0x3) : parse_post_decrypt;
            // If not recic, this is an encrypted packet, yet to be decrypted
            (0x0 &&& 0x1, 0x0 &&& 0x0) : parse_esp;
            default                    : reject;
        }
    }
    state parse_post_decrypt {
        main_meta.ipsec_decrypt_done = 1;

        pkt.extract(hdr.esp);
        pkt.extract(hdr.esp_iv);

        // Next header is the decrypted inner ip header parse it again.
        // Pipeline code will have to check the decrypt results and
        // remove any pad, esp trailer and esp auth data
        transition parse_ipv4;
    }
    state parse_esp {
        pkt.extract(hdr.esp);
        pkt.extract(hdr.esp_iv);
        main_meta.sa_index = hdr.esp.spi;
        transition accept;
    }
    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition accept;
    }
}

/// This example assumes ESP implementaion as described in rfc 4303
/// The packet format for encapsulated packet on the wire is as follows (from RFC)
///      0                   1                   2                   3
///      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
///    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///    |               Security Parameters Index (SPI)                 |
///    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///    |                      Sequence Number                          |
///    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+---
///    |                    IV (optional)                              | ^ p
///    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+ | a
///    |                    Rest of Payload Data  (variable)           | | y
///    ~                                                               ~ | l
///    |                                                               | | o
///    +               +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+ | a
///    |               |         TFC Padding * (optional, variable)    | v d
///    +-+-+-+-+-+-+-+-+         +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+---
///    |                         |        Padding (0-255 bytes)        |
///    +-+-+-+-+-+-+-+-+-+-+-+-+-+     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///    |                               |  Pad Length   | Next Header   |
///    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///    |         Integrity Check Value-ICV   (variable)                |
///    ~                                                               ~
///    |                                                               |
///    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

control ipsec_crypto( inout headers_t hdr,
                      inout main_metadata_t main_meta,
                      in pna_main_input_metadata_t istd)
{
    action ipsec_esp_decrypt(bit<32> spi,
                             bit<32> salt,
                             bit<256> key,
                             bit<9> key_size,
                             bit<1> ext_esn_en,
                             bit<1> enable_auth,
                             bit<64> esn) {

        // IV(nonce) needed for AES-GCM algorithm
        // it consists of iv that is sent on the wire plus an internally maintained salt value
        bit<128> iv = (bit<128>)(salt ++ hdr.esp_iv.iv);
        ipsec_acc.set_iv(iv);

        ipsec_acc.set_key(key, key_size);

        // Add protocol specific auth data and provide its offset and len
        bit<16> aad_offset = hdr.ethernet.minSizeInBytes() + 
                             hdr.ipv4_1.minSizeInBytes();

        // For this exmaple 32bit seq num is used
        // ESP header - spi and 32bit seq number are included in ICV computation. These are
        // considered as AAD (additional Auth data) here. If 64bit seq number is used, the
        // upper 32bits of the ESN must be included in the AAD.
        bit<16> aad_len = hdr.esp.minSizeInBytes();

        // Action parameter esn is expected to be stateful, i.e. the following operations
        // esn checking / anti-replay attack prevention is not shown in this example
        // as it can be implemented in P4 pipeline and does not affect use of 
        // the extern object shown in this example
        ipsec_acc.set_auth_data_offset(aad_offset);
        ipsec_acc.set_auth_data_len(aad_len);

        // payload_offset : points inner(original) ip header which follows the esp_iv header
        // It is possible to remove the outer (tunnel) headers if desired, this example
        // retains those headers during decrypt operation and removes them on recirc
        bit<16> encr_pyld_offset = aad_offset + aad_len + hdr.esp_iv.minSizeInBytes();
        ipsec_acc.set_payload_offset(encr_pyld_offset);

        // Encrypted payload_len
        // Remove protocol specific header (E.g. RFC4106)
        bit<16> encr_pyld_len = hdr.ipv4_1.totalLen - hdr.ipv4_1.minSizeInBytes() -
                                hdr.esp.minSizeInBytes() - hdr.esp_iv.minSizeInBytes();


        ipsec_acc.set_payload_offset(encr_pyld_offset);
        ipsec_acc.set_payload_len(encr_pyld_len);

        ipsec_acc.enable_decrypt(enable_auth);

        // recirc
        // add a recirc header to provide decrption info to parser
        hdr.recirc_header.ipsec_op = IPSEC_OP_DECRYPT;
        hdr.recirc_header.ipsec_len = encr_pyld_len;
        hdr.recirc_header.setValid();

        // TODO: recirc_packet() is hardware specific extern, or it can be standardized
        recirc_packet();
    }

    action ipsec_esp_encrypt(bit<32> spi,
                             bit<32> salt,
                             bit<256> key,
                             bit<9> key_size,
                             bit<1> ext_esn_en,
                             bit<1> enable_auth,
                             bit<64> esn) {

        // update sequence number for each transmitted packet
        // This can be done using stateful registers currently defined in P4
        // it is not shown in this example
        // esn = esn + 1;

        // Set IV information needed for encryption
        // For ipsec combine salt and esn
        bit<128> iv = (bit<128>)(salt ++ esn);
        ipsec_acc.set_iv(iv);

        ipsec_acc.set_key(key, key_size);

        // For tunnel mode, operation, copy original IP header that needs to
        // be encrypted. This header will be emitted after ESP header.
        hdr.ipv4_2 = hdr.ipv4_1;
        hdr.ipv4_2.setValid();

        // Add protocol specific headers to the packet (rfc4106)
        // 32bit seq number is used
        hdr.esp.spi = spi;
        hdr.esp.seq = esn[31:0];
        hdr.esp.setValid();

        hdr.esp_iv.iv = esn;
        hdr.esp_iv.setValid();

        // update tunnel ip header
        hdr.ipv4_1.totalLen = hdr.ipv4_2.totalLen + hdr.esp.minSizeInBytes() +
                              hdr.esp_iv.minSizeInBytes();
        // Set outer header's next header as ESP
        hdr.ipv4_1.protocol = IP_PROTO_ESP;

        bit<16> aad_offset = hdr.ethernet.minSizeInBytes() + 
                             hdr.ipv4_1.minSizeInBytes();
        bit<16> aad_len = hdr.esp.minSizeInBytes();

        ipsec_acc.set_auth_data_offset(aad_offset);
        ipsec_acc.set_auth_data_len(aad_len);

        // payload_offset : points inner(original) ip header which follows the esp header
        bit<16> encr_pyld_offset = aad_offset + aad_len;
        ipsec_acc.set_payload_offset(encr_pyld_offset);

        // payload_len : data to be encrypted
        // Remove protocol specific header (E.g. RFC4106)
        bit<16> encr_pyld_len = hdr.ipv4_2.totalLen;

        ipsec_acc.set_payload_len(encr_pyld_len);

        // TODO: compute padding, build esp_trailer etc.

        // instruct engine to add icv after encrypted payload
        ipsec_acc.set_icv_offset(ICV_AFTER_PAYLOAD);
        ipsec_acc.set_icv_len(32w4); // Four bytes of ICV value.

        // run encryption w/ authentication
        ipsec_acc.enable_encrypt(enable_auth);
    }

    action ipsec_sa_action(bit<32>    spi,
                           bit<32>    salt,
                           bit<256>   key,
                           bit<9>     key_size,
                           bit<1>     ext_esn_en,
                           bit<1>     auth_en,
                           bit<1>     valid_flag,
                           bit<64>    esn) {
        if (valid_flag == 0) {
            return;
        }
        if (!hdr.esp.isValid()) {
            ipsec_esp_encrypt(spi, salt, key, key_size, ext_esn_en, auth_en, esn);
        } else {
            ipsec_esp_decrypt(spi, salt, key, key_size, ext_esn_en, auth_en, esn);
        }
    }
    // setup crypto accelerator for encryption/decryption - get info from sa table
    // lookup sa_table using esp.spi
    //  In this example same SA index is used for encrypt/decrypt, in real
    // implementation it can be separated into two entries
    table ipsec_sa {
        key = {
            // For encrypt case get sa_idx from parser
            // for decrypt case esp hdr spi value will be used as sa_idx
            main_meta.sa_index  : exact;
        } 
        actions = {
            ipsec_sa_action;
        }
        // default_action = ipsec_sa_action;
    }
    apply {
        ipsec_sa.apply();
    }
}

control ipsec_post_decrypt(
    inout headers_t       hdr,
    inout main_metadata_t main_meta,
    in    pna_main_input_metadata_t  istd)
{
    action ipsec_post_decrypt_action() {
        // post decrypt processing happens here
        // E.g. remove any unrequired headers such as outer headers in tunnel mode etc..
        if (ipsec_acc.get_results() != crypto_results_e.SUCCESS) {
            // TODO:
            // Check if this is AUTH error or some other error.
            // Drop the packet or do other things as needed
            drop_packet();
            return;
        }
        // remove outer (tunnel headers), make inner header
        hdr.ipv4_1 = hdr.ipv4_2;
        hdr.ipv4_2.setInvalid();

        // Remove ipsec related headers from the packet
        hdr.esp.setInvalid();
        hdr.esp_iv.setInvalid();

        // Process rest of packet as required
        // ...
        return;
    }
    table ipsec_post_decrypt_table {
        actions = {
            ipsec_post_decrypt_action;
        }
        // default_action = ipsec_post_decrypt_action;
    }
    apply {
        ipsec_post_decrypt_table.apply();
    }
}

control MainControlImpl(
    inout headers_t       hdr,
    inout main_metadata_t main_meta,
    in    pna_main_input_metadata_t  istd,
    inout pna_main_output_metadata_t ostd)
{
    apply {
        if (main_meta.ipsec_decrypt_done == 1) {
            ipsec_post_decrypt.apply(hdr, main_meta, istd);
        } else {
            ipsec_crypto.apply(hdr, main_meta, istd);
        }
    }
}

control MainDeparserImpl(
    packet_out pkt,
    in    headers_t hdr,                // from main control
    in    main_metadata_t user_meta,    // from main control
    in    pna_main_output_metadata_t ostd)
{
    apply {
        pkt.emit(hdr.recirc_header);
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4_1);
        pkt.emit(hdr.esp);
        pkt.emit(hdr.esp_iv);
        pkt.emit(hdr.ipv4_2);
        pkt.emit(hdr.tcp);
        pkt.emit(hdr.udp);
    }
}

// Package_Instantiation
PNA_NIC(
    MainParserImpl(),
    MainControlImpl(),
    MainDeparserImpl()
    ) main;
