#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <mfast.h>
#include <mfast/coder/fast_decoder.h>
#include <mfast/xml_parser/dynamic_templates_description.h>
#include <arpa/inet.h>
#include <unistd.h>

static const char* SERVER_IP   = "127.0.0.1";
static const int   SERVER_PORT = 9001;
static const char* TEMPLATE_FILE = TEMPLATE_DIR "/SimpleMD.xml";


using mfast::templates_description;
using mfast::dynamic_templates_description;
using mfast::fast_decoder;
using mfast::message_cref;
using mfast::ascii_string_cref;


int main() {
    using namespace mfast;

    try {
        std::ifstream t(TEMPLATE_FILE);
        if (!t) {
            std::cerr << "Erro abrindo template" << std::endl;
            return 1;
        }
        std::stringstream buffer;
        buffer << t.rdbuf();
        std::string xml_content = buffer.str();
        dynamic_templates_description desc(xml_content.c_str());
        const templates_description* descriptions[] = {&desc};

        fast_decoder decoder;
        decoder.include(descriptions);

        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) { perror("socket"); return 1; }

        sockaddr_in serv{};
        serv.sin_family = AF_INET;
        serv.sin_port   = htons(SERVER_PORT);
        inet_pton(AF_INET, SERVER_IP, &serv.sin_addr);

        if (connect(sock, (sockaddr*)&serv, sizeof(serv)) < 0) {
            perror("connect");
            return 1;
        }

        std::vector<char> buf(8192);
        std::ofstream dump("mfast_dump.txt");

        while (true) {
            ssize_t n = read(sock, buf.data(), buf.size());
            if (n <= 0) break;

            const char* p   = buf.data();
            const char* end = buf.data() + n;

            while (p < end) {
                message_cref msg = decoder.decode(p, end);

                ascii_string_cref symbol = static_cast<ascii_string_cref>((msg)[0]);
                ascii_string_cref side   = static_cast<ascii_string_cref>((msg)[1]);
                mfast::decimal_cref price = static_cast<mfast::decimal_cref>((msg)[2]);
                mfast::uint32_cref qty    = static_cast<mfast::uint32_cref>((msg)[3]);
                mfast::uint32_cref seq    = static_cast<mfast::uint32_cref>((msg)[4]);

                dump << "SYMBOL=" << symbol.c_str()
                    << " SIDE="  << side.c_str()
                    << " PRICE=" << price.value()
                    << " QTY="   << qty.value()
                    << " SEQ="   << seq.value()
                    << "\n";
                dump.flush();
            }
        }

        close(sock);
    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
