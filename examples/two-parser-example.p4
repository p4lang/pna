//BEGIN:PreParserImpl_interface
parser PreParserImpl (
    packet_in pkt,
    out headers_t hdr,
    out metadata_t user_meta,
    in  pna_parser_input_metadata_t istd)
//END:PreParserImpl_interface
{}

//BEGIN:MainParserImpl_interface
parser MainParserImpl(
    packet_in pkt,
    out headers_t hdr,
    out metadata_t user_meta,
    in  pna_parser_input_metadata_t istd)
//END:MainParserImpl_interface
{}


// BEGIN:Package_Instantiation_Example
PNA_NIC(
    PreParserImpl(),
    PreControlImpl(),
    MainParserImpl(),
    MainControlImpl(),
    MainDeparserImpl()) main;
// END:Package_Instantiation_Example
