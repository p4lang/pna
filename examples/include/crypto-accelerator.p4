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

/// Crypto accelerator object is instantiated for each crypto algorithm
enum crypto_algorithm_e {
    AES_GCM
}

/// Results from crypto accelerator
enum crypto_results_e {
    SUCCESS,
    AUTH_FAILURE,
    HW_ERROR
}

enum crypto_mode_e {
    TUNNEL,
    TRANSPORT,
    TRANSPORT_NAT_T
}

/// special value to indicate that ICV is after the crypto payload
#define ICV_AFTER_PAYLOAD ((int<32>)-1)

/// The crypto_accelerator engine used in this example uses AES-GCM algorithm.
/// It is assumed to be agnostic to wire protocols i.e. does not understand protocol 
/// specific headers like ESP, AH etc
///
/// The crypto accelerator does not modify the packet outside the payload area and ICV
///     Any wire-protocol header, trailer add/remove is handled by P4 pipeline
///     The engine does not perform additional functions such as anti-replay protection, it
///     is done in P4 pipeline
/// 
/// Crypto Engine takes the following inputs:
///     - key, iv, icv_location/size, enable_auth, auth_data (aka AAD), payload location
///     In some protocols AAD can be present in the packet (e.g ESP header), in that case AAD
///         can be specified as offset/len within the packet. Additional auth data 
///         that is not part of the packet can also be provided
///     On encrypt operation, icv_location/size indicates that icv is inserted in the
///         packet at the specified packet offset
///     On decrypt operation, icv_location and size is used for auth validation
///
/// Example:
/// Encrypt operation:
///     Parameters passed : key, iv, icv_location/size, enable_auth, auth_data
///     Packet presented to the engine -
///     +------------------+--------------------------+-----------+
///     | Headers not to   | Encryption protocol      | payload   | 
///     | be Encrypted     | headers (E.g Esp, Esp-IV)|           |
///     +------------------+-----------------------  -+-----------+
///     Packet after Encryption:
///     +------------------+--------------------------+-----------+-----------+
///     | Headers not to   | Encryption protocol      | Encrypted | ICV (opt) |
///     | be Encrypted     | headers (E.g Esp, Esp-IV)| Payload   |           |
///     +------------------+--------------------------+-----------+-----------+
///     ICV can be inserted either before or right after the encrypted payload 
///     as specified by icv_location/size
///     Results: Success, Hardware Error
///
/// Decrypt operation:
///     Parameters passed : key, iv, icv_location/size, enable_auth, auth_data
///     Packet presented to the engine -
///     +------------------+--------------------------+-----------+-----+
///     | Headers not to   | Encryption protocol      | Encrypted | ICV |
///     | Encrypted        | headers (E.g Esp, Esp-IV)| Payload   |     |
///     +------------------+--------------------------+-----------+-----+
///     Packet after decrytion:
///     +------------------+--------------------------+-----------+-----+
///     | Headers not to   | Encryption protocol      | cleartext | ICV |
///     | Encrypted        | headers (E.g Esp, Esp-IV)| Payload   |     |
///     +------------------+--  ----------------------+-----------+-----+
///     Results: Success, Auth Failure, Hardware Error
///

// BEGIN:Crypto_accelerator_extern_object

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

    // The format of the auth data is not specified/mandated by this object definition
    // If it is part of the packet, it can be specified using offset/len mothods below
    void set_auth_data_offset<T>(in T offset);
    void set_auth_data_len<T>(in T len);

    // Alternatively: Following API can be used to consturct the auth_data and
    // provide it to the engine.
    void add_auth_data<H>(in H auth_data);

    // Auth trailer aka ICV is added by the engine after doing encryption operation
    // Specify icv location - when a wire protocol wants to add ICV in a specific location (e.g. AH)
    // The following apis can be used to specify the location of ICV in the packet
    // A special offset indicates ICV is after the payload
    void set_icv_offset<T>(in T offset);
    void set_icv_len<L>(in L len);

    // setup payload to be encrypted/decrypted
    void set_payload_offset<T>(in T offset);
    void set_payload_len<T>(in T len);
    
    // crypto accelerator runs at the end of the pipeline (after deparser), the following
    // methods will enable the accelerator to run encrypt/decrypt operations
    // enable_auth flag enables authentication check for decrypt. For encrypt operation,
    // auth data computed, is added to specified icv_offset/len
    void enable_encrypt<T>(in T enable_auth);
    void enable_decrypt<T>(in T enable_auth);

    // crypto accelerator runs immediately and returns control flow to the current pipeline
    // stage. The method is responsible for defining the contents of the ESP header, 
    // calculating the payload offset and lengths, encrypting the payload appropriately and 
    // reparsing the packet. User can decide if to proceed or reinject.
    //
    // Pre-conditions: The parser must have been executed prior to this extern. The packet 
    // headers and metadata from the parser are provided as inout params.
    // Post-conditions: The deparser will be executed prior to encapsulation, the packet 
    // bytestream will be updated and encryption will be performed on the payload. The 
    // packet will be reparsed and parser states updated.
    // Side-effects: parser states will be re-evaluated if crypto has succeeded.
    //
    // H - inout Headers is the output of the parser block
    // M - inout Metadata is from the parser block and shared with the control 
    // T - in enable_auth flag enables authentication check
    // S - in seq is the optional sequence number
    // I - in iv is the initialization vector
    crypto_results_e encrypt_inline<H,M,T,S,I>(packet_in pkt,
                        inout H hdr, 
                        inout M meta,
                        in crypto_mode_e mode,
                        in T enable_auth,
                        in bit<32> spi,
                        in S seq,
                        in I iv);

    // crypto accelerator runs immediately and returns control flow to the current pipeline
    // stage. The method is responsible for decrypting the payload appropriately, removing
    // the ESP header, calculating the payload offset and lengths, and reparsing the packet.
    // The user should then check the status.
    //
    // Pre-conditions: The parser will have been executed prior to this extern. The packet 
    // headers and metadata from the parser are provided as inout params.
    // Post-conditions: The deparser will be executed prior to decapsulation, the packet
    // bytestream will be updated and decryption will be performed on the payload. The 
    // packet will be reparsed and parser states recalculated.
    // Side-effects: parser states will be re-evaluated if crypto has succeeded.
    //
    // H - inout Headers is the output of the parser block
    // M - inout Metadata is from the parser block and shared with the control 
    // T - in enable_auth flag enables authentication check
    // S - in seq is the optional sequence number
    crypto_results_e decrypt_inline<H,M,T,S>(packet_in pkt,
                        inout H hdr,
                        inout M meta,
                        in crypto_mode_e mode,
                        in T enable_auth,
                        in S seq);

    // disable crypto engine. Between enable and disable methods,
    // whichever method is called last overrides the previous calls
    void disable();

    // get results of the previous operation
    crypto_results_e get_results();
}
// END:Crypto_accelerator_extern_object
