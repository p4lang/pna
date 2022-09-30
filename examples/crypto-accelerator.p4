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

/// Crypto accelerator Extern
enum bit<8> crypto_algorithm_e {
    AES_GCM = 1
}
enum bit<8> crypto_results_e {
    SUCCESS = 0,
    AUTH_FAILURE = 1,
    HW_ERROR = 2
}

#define ICV_AFTER_PAYLOAD ((int<32>)-1)
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
    // crypto accelerator runs at the end of the pipeline (after deparser), the following
    // methods will enable the accelerator to run encrypt/decrypt operations
    void enable_encrypt<T>(in T enable_auth);
    void enable_decrypt<T>(in T enable_auth);

    // disable crypto engine
    void disable();

    crypto_results_e get_results();       // get results of the previous operation
}
