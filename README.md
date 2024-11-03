Solana Validator Balance Monitor and Ping Utility
This codebase is a server application built with Node.js, Express, and Solana Web3.js. It serves two primary functions:

Monitoring Solana Validator Balances: The code checks and manages the balance of two accounts (id.json and withdrawer.json), ensuring funds are maintained at specific levels to support operations and transfers.
Tracking Solana Validator Ping Times: The code tracks ping times to the Solana validator node, providing insights into response times and network latency.

Features
Dynamic IP Detection
Balance Check & Automatic Transfers: Every 24 hours (configurable interval), the server:
Checks the balance of the withdrawer account (withdrawer.json). If it falls below 0.1 SOL, it attempts to transfer 1 SOL from the identity account (identity.json).
Monitors the ID account balance (id.json). If it drops below 1.2 SOL, it initiates a transfer from the withdrawer account, ensuring the ID account can cover transaction fees.
Real-time Ping Tracking: The server periodically executes solana ping commands to monitor response times to the validator node. Key statistics, including average, median, 90th percentile, and minimum ping times, are calculated and exposed via an API endpoint (/ping_times).

Installation
sudo apt update
sudo apt install nodejs npm

Clone Repository and Install Dependencies:
git clone <repository-url>
cd <project-directory>
npm install express axios @solana/web3.js

Set Up Solana Keypairs: Ensure that the id.json, withdrawer.json, and identity.json keypair files are located in the appropriate directories:

~/.config/solana/id.json
~/solana/withdrawer.json
~/solana/identity.json

Set Permissions and Run the Server:
chmod +x pinger.sh
./pinger.sh
