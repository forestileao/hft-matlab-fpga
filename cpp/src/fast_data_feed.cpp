
#include "SimpleMD.h"
#include <mfast/coder/fast_encoder.h>
#include <iostream>
#include <map>
#include <vector>
#include <set>
#include <random>
#include <chrono>
#include <thread>
#include <mutex>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include "fast_data_feed.h"

static const int PORT = 9001;

std::mutex clients_mutex;
std::set<int> clients;

void accept_loop(int server_fd)
{
    while (true) {
        sockaddr_in addr{};
        socklen_t len = sizeof(addr);
        int fd = accept(server_fd, (sockaddr*)&addr, &len);
        if (fd < 0) continue;
        std::cout << "Client connected (fd=" << fd << ")\n";
        std::lock_guard<std::mutex> lock(clients_mutex);
        clients.insert(fd);
    }
}

int main()
{
    // --- server socket ---
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) { perror("socket"); return 1; }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons(PORT);

    if (bind(server_fd, (sockaddr*)&addr, sizeof(addr)) < 0) { perror("bind"); return 1; }
    if (listen(server_fd, 10) < 0)                           { perror("listen"); return 1; }

    std::cout << "Feed server listening on port " << PORT << "\n";

    std::thread(accept_loop, server_fd).detach();

    // --- mfast encoder ---
    mfast::fast_encoder encoder;
    const mfast::templates_description* descs[] = { SimpleMD::description() };
    encoder.include(descs);

    // --- random generators ---
    const std::vector<std::string> symbols = { "AAPL", "MSFT", "NVDA", "GOOGL", "TSLA" };
    const std::vector<std::string> sides   = { "buy", "sell" };

    std::map<std::string, double> base_price = {
        { "AAPL",  185.0 },
        { "MSFT",  415.0 },
        { "NVDA",  875.0 },
        { "GOOGL", 170.0 },
        { "TSLA",  175.0 },
    };

    std::mt19937 rng(std::random_device{}());
    std::uniform_int_distribution<int> sym_dist(0, (int)symbols.size() - 1);
    std::uniform_int_distribution<int> side_dist(0, (int)sides.size() - 1);
    std::uniform_int_distribution<int> qty_dist(100, 5000);
    std::normal_distribution<double>   price_noise(0.0, 0.5);

    uint32_t seq = 1;
    char encode_buf[1024];

    while (true) {
        const std::string& sym  = symbols[sym_dist(rng)];
        const std::string& side = sides[side_dist(rng)];
        double price = base_price.at(sym) + price_noise(rng);
        price = static_cast<int>(price * 100) / 100.0;
        int qty = qty_dist(rng);

        SimpleMD::SimpleMD message;
        SimpleMD::SimpleMD_mref ref = message.ref();
        ref.set_MDEntries().resize(1);
        SimpleMD::SimpleMD_mref::MDEntries_element_mref entry(ref.set_MDEntries()[0]);

        entry.set_Symbol().as(sym.c_str());
        entry.set_Side().as(side.c_str());
        entry.set_Price().as(price);
        entry.set_Qty().as(qty);
        entry.set_SeqNo().as(seq);

        std::size_t encoded_len = encoder.encode(ref, encode_buf, sizeof(encode_buf), true);

        std::cout << "seq=" << seq
                  << " sym=" << sym << " side=" << side
                  << " price=" << price << " qty=" << qty
                  << " (" << encoded_len << " bytes)\n";
        ++seq;

        // broadcast to all connected clients
        {
            std::lock_guard<std::mutex> lock(clients_mutex);
            std::set<int> dead;
            uint32_t frame_len = htonl((uint32_t)encoded_len);
            for (int fd : clients) {
                ssize_t s1 = send(fd, &frame_len, sizeof(frame_len), MSG_NOSIGNAL | MSG_MORE);
                ssize_t s2 = send(fd, encode_buf, encoded_len, MSG_NOSIGNAL);
                if (s1 < 0 || s2 < 0) dead.insert(fd);
            }
            for (int fd : dead) {
                std::cout << "Client disconnected (fd=" << fd << ")\n";
                close(fd);
                clients.erase(fd);
            }
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    close(server_fd);
    return 0;
}
