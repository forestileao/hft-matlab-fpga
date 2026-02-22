#include "SimpleMD.h"
#include <mfast/coder/fast_decoder.h>
#include <iostream>
#include <vector>
#include <boost/exception/diagnostic_information.hpp>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>

static const char* SERVER_IP   = "127.0.0.1";
static const int   SERVER_PORT = 9001;

int main()
{
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

    std::cout << "Connected to " << SERVER_IP << ":" << SERVER_PORT << "\n";

    mfast::fast_decoder decoder;
    const mfast::templates_description* descs[] = { SimpleMD::description() };
    decoder.include(descs);

    auto read_exact = [&](void* dst, size_t len) -> bool {
        char* p = static_cast<char*>(dst);
        size_t remaining = len;
        while (remaining > 0) {
            ssize_t n = read(sock, p, remaining);
            if (n <= 0) return false;
            p += n;
            remaining -= n;
        }
        return true;
    };

    std::vector<char> buf(8192);

    while (true) {
        uint32_t frame_len_net;
        if (!read_exact(&frame_len_net, sizeof(frame_len_net))) break;
        uint32_t msg_len = ntohl(frame_len_net);

        if (msg_len > buf.size()) buf.resize(msg_len);
        if (!read_exact(buf.data(), msg_len)) break;

        const char* p   = buf.data();
        const char* end = buf.data() + msg_len;

        try {
            mfast::message_cref msg = decoder.decode(p, end, true);
            SimpleMD::SimpleMD_cref typed(msg);

            for (auto entry : typed.get_MDEntries()) {
                std::cout
                    << "seq="    << entry.get_SeqNo().value()
                    << " sym="   << entry.get_Symbol().c_str()
                    << " side="  << entry.get_Side().c_str()
                    << " price=" << entry.get_Price().value()
                    << " qty="   << entry.get_Qty().value()
                    << "\n";
            }
        } catch (const boost::exception& e) {
            std::cerr << "FAST decode error (msg_len=" << msg_len << "):\n"
                      << boost::diagnostic_information(e) << "\n";
            break;
        } catch (const std::exception& e) {
            std::cerr << "Decode error: " << e.what() << "\n";
            break;
        }
    }

    close(sock);
    return 0;
}
