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

#include <core.p4>
#include "../pna.p4"

/// Crypto accelerator extern
enum bit<8> crypto_algorithm_e {
    AES_GCM = 1
}
enum bit<8> crypto_results_e {
    SUCCESS = 0,
    AUTH_FAILURE = 1,
    HW_ERROR = 2
}

extern crypto_accelerator {
    /// constructor
    /// Some methods provided in this object may be specific to an algorithm used.
    /// Compiler may be able to check and warn/error when incorrect methods are used
    crypto_accelerator(crypto_algorithm_e algo);


    // security association index for this security session
    // Some implementations do not need it.. in that case this method should result in no-op
    void set_sa_index<T>(in T sa_index);

    // Set the initialization data based on protocol used. E.g. salt, random number/ counter for ipsec
    void set_iv<T>(in T iv);
    void set_key<T,S>(in T key, in S key_size);   // 128, 192, 256

    // authentication data format is protocol specific
    // Add this data as a header into the packet and provide its offset and length using the
    // following APIs
    // The format of the auth data is not specified/mandated by this object definition
    void set_auth_data_offset<T>(in T offset);
    void set_auth_data_len<T>(in T len);

    // Alternatively: Following API can be used to consturct protocol specific auth_data and
    // provide it to the engine.
    void add_auth_data<H>(in H auth_data);

    // Auth trailer aka ICV is added by the engine after doing encryption operation
    // Specify icv location - when a wire protocol wants to add ICV in a specific location (e.g. AH)
    // The following apis can be used to specify the location of ICV in the packet
    // special offset (TBD) indicates ICV is after the payload
    void set_icv_offset<T>(in T offset);
    void set_icv_len<L>(in L len);

    // setup payload to be encrypted/decrypted
    void set_payload_offset<T>(in T offset);
    void set_payload_len<T>(in T len);
    
    // operation
    void encrypt<T>(in T enable_auth);
    void decrypt<T>(in T enable_auth);

    // disable engine
    void disable();

    crypto_results_e get_results();       // get results of the previous operation
}

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

header esp_iv_h {
    bit<64>     iv; // IV on the wire excludes the salt
}

header esp_trailer_pad_byte3 {
    bit<24> pad3;
}

header esp_trailer_pad_byte2 {
    bit<16> pad2;
}

header esp_trailer_pad_byte1 {
    bit<8> pad1;
}

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

    esp_trailer_pad_byte1 pad_byte1;
    esp_trailer_pad_byte2 pad_byte2;
    esp_trailer_pad_byte3 pad_byte3;
}

/// Metadata

struct main_metadata_t {
    // empty for this skeleton
}

control PreControlImpl(
    in    headers_t  hdr,
    inout main_metadata_t meta,
    in    pna_pre_input_metadata_t  istd,
    inout pna_pre_output_metadata_t ostd)
{
    apply {
        // Not used in this example
    }
}

parser MainParserImpl(
    packet_in pkt,
    out   headers_t       hdr,
    inout main_metadata_t main_meta,
    in    pna_main_parser_input_metadata_t istd)
{
    bit<1> is_recirc = 0;
    bit<2>  ipsec_op = 0;

    state start {
        transition select(istd.loopedback) {
            1 : parse_recirc_header;
            default : parse_packet;
        }
    }

    state parse_recirc_header {
        packet.extract(hdr.recirc_header);
        is_recirc = 1;
        ipsec_op = hdr.recirc_header.ipsec_op;
        // TODO: 
        // transition parse_packet;
    }

    state parse_packet {
        main_meta.sa_index = 1; // just for exmaple, used for encrypt
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            ETHERTYPE_CTAG : parse_ctag;
            ETHERTYPE_IPV4 : parse_ipv4;
            default : accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4_1);
        main_meta.key_metadata.ipv4_src = hdr.ipv4_1.srcAddr;
        main_meta.key_metadata.ipv4_dst = hdr.ipv4_1.dstAddr;
        transition select(hdr.ipv4_1.protocol) {
            IP_PROTO_TCP        : parse_tcp;
            IP_PROTO_UDP        : parse_udp;
            IP_PROTO_ESP        : parse_crypto;
            default             : accept;
        }
    }

    state parse_crypto {
        transition select(is_recirc, ipsec_op) {
            (0x1 &&& 0x1, 0x1 &&& 0x3) : parse_post_decrypt;
            // If not recic, this is an encrypted packet, yet to be decrypted
            (0x0 &&& 0x1, 0x0 &&& 0x0) : parse_esp;
            default                    : reject;
        }
    }
    state parse_post_decrypt {
        main_meta.ipsec_decrypt_done = 1;
        // on recirc after decrypt, remove the ESP headers
        // TODO: check decrypt error and drop on error
        transition reject;

        // packet.extract(hdr.esp);
        // packet.extract(hdr.esp_iv);

        // Next header is the decrypted ip header parse it again.
        // Pipeline code will have to check the decrypt results and
        // remove any pad, esp trailer and esp auth data
        // transition parse_ipv4;
    }
    state parse_esp {
        packet.extract(hdr.esp);
        packet.extract(hdr.esp_iv);
        main_meta.sa_index = hdr.esp.spi;   // used for decrypt
        transition accept;
    }
    state parse_tcp {
        packet.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        packet.extract(hdr.udp);
        transition accept;
    }
}


control ipsec_crypto(
    inout headers_t       hdr,
    inout main_metadata_t main_meta,
    in    pna_main_input_metadata_t  istd)
{
    action ipsec_esp_decrypt(in bit<32> spi,
                             in bit<32> salt,
                             in bit<256> key,
                             in bit<9>  key_size,
                             in bit<1>  ext_esn_en,
                             in bit<1>  enable_auth,
                             inout bit<64> esn) {
        // TODO check the seq number and update local seq num (optional) - not done here

        ipsec_acc.init(crypto_algorithm_e.AES_GCM);

        bit<64>     seq_no;
        seq_no[31:0] = hdr.esp.seq;
        seq_no[63:32] = esn[63:32];

        // build IPSec specific IV
        bit<128> iv = (bit<128>)(salt ++ hdr.esp_iv.iv);
        ipsec_acc.set_iv(iv);

        bit<32> aad_len = 0;
        esp_aad_setup(spi, seq_no, ext_esn_en, aad_len);

        ipsec_acc.set_key(key, key_size);

        ipsec_acc.set_payload_offset((bit<32>)0);
        ipsec_acc.set_payload_len((bit<32>)0);

        ipsec_acc.decrypt(enable_auth);

        // recirc
        // add a recirc header to provide decrption info to parser
    }

    action ipsec_esp_encrypt(in bit<32> spi,
                             in bit<32> salt,
                             in bit<256> key,
                             in bit<9>  key_size,
                             in bit<1>  ext_esn_en,
                             in bit<1>  enable_auth,
                             in bit<64> esn) {

        // Initialize the ipsec accelerator
        ipsec_acc.init(crypto_algorithm_e.AES_GCM);
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

        // In this example which is an ipsec example using ESP header,
        // the position of ESP header in the outgoing packet and size of
        // ESP header is provided to accelerator  using methods
        // set_auth_data_offset() and set_auth_data_len()
        bit<32> aad_len = hdr.esp.minSizeInBytes();;
        hdr.esp.spi = spi;
        hdr.esp.setValid();
        bit<32> aad_offset = (bit<32>)(metadata.offset_metadata.l2 +
                                       hdr.ethernet.minSizeInBytes() +
                                       hdr.ipv4_1.minSizeInBytes());
        ipsec_acc.set_auth_data_offset(aad_offset);
        ipsec_acc.set_auth_data_len(aad_len);

        // payload_offset : points inner(original) ip header which follows the esp header
        bit<32> encr_pyld_offset = aad_offset + aad_len;
        ipsec_acc.set_payload_offset(encr_pyld_offset);

        bit<32> encr_pyld_len;
        encr_pyld_len[15:8] = metadata.control_metadata.l4_len_hi;
        encr_pyld_len[7:0 ] = metadata.control_metadata.l4_len_lo;

        // Include original ip header that is tunneled into the encr_pyld_len.
        bit<16> ip_hdr_len = hdr.ipv4_1.ihl << 2;
        encr_pyld_len = ip_hdr_len + encr_pyld_len + hdr.esp_trailer.minSizeInBytes();
        ipsec_acc.set_payload_len(encr_pyld_len);

        // Add esp trailer
        hdr.esp_trailer.setValid();
        bit<8> pad_len = encr_pyld_len & 3;
        hdr.esp_trailer.pad_len = pad_len;

        // RFC 4303 recommends minimal padding and right aligned to 32bit word.
        // Add pad bytes to packet.
        if (pad_len == 3) {
            hdr.pad_byte3 = 3;
            hdr.pad_byte3.setValid();
        } else if (pad_len == 2) {
            hdr.pad_byte2 = 2;
            hdr.pad_byte2.setValid();
        } else if (pad_len == 1) {
            hdr.pad_byte1 = 1;
            hdr.pad_byte1.setValid();
        }

        hdr.esp_trailer.next_hdr = hdr.ipv4_1.protocol;

        // methods set_icv_offset() and set_icv_len() provide pointer to accelerator
        // to store computed value. This example program lets accelerator store icv
        // value after the esp_trailer.
        ipsec_acc.set_icv_offset(encr_pyld_offset + encr_pyld_len);
        ipsec_acc.set_icv_len(4); // Four bytes of ICV value.

        // Set outer header's next header as ESP
        hdr.ipv4_1.protocol = IP_PROTO_ESP;

        // run encryption w/ authentication
        ipsec_acc.encrypt(enable_auth);

    }

    @name (".ipsec_sa_action")
    action ipsec_sa_lookup_action(in bit<32>    spi,
                                  in bit<32>    salt,
                                  in bit<256>   key,
                                  in bit<9>     key_size,
                                  in bit<1>     ext_esn_en,
                                  in bit<1>     auth_en,
                                  in bit<1>     valid_flag,
                                  in bit<64>    esn) {
        if (valid_flag == 0) {
            return;
        }
        if (!hdr.esp.isValid()) {
            ipsec_esp_encrypt(spi, salt, key, key_size, ext_esn_en, auth_en, esn);
        } else {
            ipsec_esp_decrypt(spi, salt, key, key_size, ext_esn_en, auth_en, esn);
        }
    }
    // setup crypto accelerator for decryption - get info from sa table
    // lookup sa_table using esp.spi
    table ipsec_sa {
        key = {
            // For encrypt case get sa_idx from parser
            // for decrypt case esp hdr spi value will be used as sa_idx
            main_meta.sa_index  : exact;
        } 
        actions  = {
            ipsec_sa_action;
        }
        default_action = ipsec_sa_action;
    }
}

control ipsec_post_decrypt(
    inout headers_t       hdr,
    inout main_metadata_t main_meta,
    in    pna_main_input_metadata_t  istd)
{
    // post decrypt processing happens here
    // E.g. remove any unrequired headers such as outer headers in tunnel mode etc..
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
        pkt.emit(hdr.tcp);
        pkt.emit(hdr.udp);
        pkt.emit(hdr.esp);
        pkt.emit(hdr.ipv4_2);
        pkt.emit(hdr.esp_iv);
        pkt.emit(hdr.pad_byte1);
        pkt.emit(hdr.pad_byte2);
        pkt.emit(hdr.pad_byte3);
    }
}

// Package_Instantiation
PNA_NIC(
    MainParserImpl(),
    PreControlImpl(),
    MainControlImpl(),
    MainDeparserImpl()
    ) main;
