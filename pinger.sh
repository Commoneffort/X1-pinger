const express = require('express');
const { spawn } = require('child_process');
const net = require('net');
const { Connection, Keypair, SystemProgram, Transaction } = require('@solana/web3.js');
const axios = require('axios');
const os = require('os');
const app = express();
const port = 3334;

const ID_JSON_PATH = `${os.homedir()}/.config/solana/id.json`;
const WITHDRAW_JSON_PATH = `${os.homedir()}/solana/withdrawer.json`;
const IDENTITY_JSON_PATH = `${os.homedir()}/solana/identity.json`;
const LAMPORTS_PER_SOL = 1000000000; // 1 SOL = 1 billion lamports

let SOLANA_URL = ''; // To be dynamically set
let pingTimes = [];

// Function to dynamically set the validator's IP
async function getValidatorIP() {
    try {
        const response = await axios.get('https://api.ipify.org?format=json');
        SOLANA_URL = `http://${response.data.ip}:8899`;
        console.log(`Validator's IP dynamically set to: ${SOLANA_URL}`);
    } catch (error) {
        console.error('Error fetching validator IP:', error.message);
    }
}

// Function to calculate the sliding average
function calculateSlidingAverage() {
    const sum = pingTimes.reduce((a, b) => a + b, 0);
    const average = (pingTimes.length > 0) ? sum / pingTimes.length : 0;
    return Math.round(average);
}

// Function to calculate the median
function calculateMedian() {
    if (pingTimes.length === 0) return 0;

    const sorted = [...pingTimes].sort((a, b) => a - b);
    const middle = Math.floor(sorted.length / 2);

    return sorted.length % 2 === 0 ? Math.round((sorted[middle - 1] + sorted[middle]) / 2) : sorted[middle];
}

// Function to calculate the 90th percentile (P90)
function calculateP90() {
    if (pingTimes.length === 0) return 0;

    const sorted = [...pingTimes].sort((a, b) => a - b);
    const index = Math.floor(0.9 * sorted.length);
    return sorted[index];
}

// Function to calculate the minimum value
function calculateMin() {
    if (pingTimes.length === 0) return 0;
    return Math.min(...pingTimes);
}

// Function to check if localhost:8899 is up
function isLocalhost8899Up() {
 return new Promise((resolve) => {
        const socket = new net.Socket();
        socket.setTimeout(1000);  // 1-second timeout

        socket.on('connect', () => {
            socket.destroy();
            resolve(true);
        });

        socket.on('timeout', () => {
            socket.destroy();
            resolve(false);
        });

        socket.on('error', () => {
            resolve(false);
        });

        socket.connect(8899, 'localhost');
    });
}

// Function to start running `solana ping` and capturing its output
async function startSolanaPing() {
    const isLocalUp = await isLocalhost8899Up();
    const pingArgs = isLocalUp ? ['ping', '-u', 'http://localhost:8899'] : ['ping', '-u', SOLANA_URL];

    if (!isLocalUp) {
        console.log('Local RPC (localhost:8899) is down. Using external Solana RPC.');
    } else {
        console.log('Local RPC (localhost:8899) is up. Using local RPC for pinging.');
    }

    const pingProcess = spawn('solana', pingArgs);

    pingProcess.stderr.on('data', (data) => {
        const lines = data.toString().split('\n');
        lines.forEach(line => {
            const match = line.match(/time=\s*(\d+)ms/);
            if (match) {
                const time = parseInt(match[1], 10);
                if (!isNaN(time)) {
                    pingTimes.push(time);
                    if (pingTimes.length > 10) pingTimes.shift();
                    console.log(`Captured ping time: ${time}ms`);
                }
            }
        });
    });

    pingProcess.on('close', (code) => {
        console.log(`solana ping process exited with code ${code}`);
        startSolanaPing();
    });
}

// Function to load keypair from JSON file
function loadKeypairFromJson(filePath) {
    const fs = require('fs');
    const secretKeyString = fs.readFileSync(filePath, 'utf8');
 const secretKey = Uint8Array.from(JSON.parse(secretKeyString));
    return Keypair.fromSecretKey(secretKey);
}

// Function to check balances and perform transfers if needed
async function checkAndWithdraw() {
    const connection = new Connection(SOLANA_URL, 'confirmed');
    let idKeypair, withdrawKeypair, identityKeypair;

    try {
        idKeypair = loadKeypairFromJson(ID_JSON_PATH);
        withdrawKeypair = loadKeypairFromJson(WITHDRAW_JSON_PATH);
        identityKeypair = loadKeypairFromJson(IDENTITY_JSON_PATH);
    } catch (error) {
        console.error('Failed to load keypair:', error.message);
        return;
    }

    // Fetching balances
    const withdrawBalance = await connection.getBalance(withdrawKeypair.publicKey);
    const idBalance = await connection.getBalance(idKeypair.publicKey);

    console.log(`Withdraw account balance: ${withdrawBalance / LAMPORTS_PER_SOL} SOL`);
    console.log(`ID account balance: ${idBalance / LAMPORTS_PER_SOL} SOL`);

    // Check if withdraw balance is less than 0.1 SOL
    if (withdrawBalance < 0.1 * LAMPORTS_PER_SOL) {
        console.log('Withdraw account balance is low, attempting to withdraw from identity.');

        // Only attempt to transfer if there are enough funds
        const amountToWithdraw = 1 * LAMPORTS_PER_SOL; // Amount to withdraw from identity to withdraw

        if (idBalance >= amountToWithdraw + 0.000005) { // Adding a small buffer for fees
            const transaction = new Transaction().add(
                SystemProgram.transfer({
                    fromPubkey: identityKeypair.publicKey,
                    toPubkey: withdrawKeypair.publicKey,
                    lamports: amountToWithdraw,
                })
            );

            try {
                const signature = await connection.sendTransaction(transaction, [identityKeypair]);
                await connection.confirmTransaction(signature);
                console.log(`Successfully transferred ${amountToWithdraw / LAMPORTS_PER_SOL} SOL from identity to withdraw.`);
            } catch (error) {
                console.error('Failed to transfer from identity to withdraw:', error.message);
                if (error.logs) {
                    console.error('Transaction logs:', await connection.getLogs(signature));
                }
            }
        } else {
            console.log('Insufficient funds in identity account to withdraw to withdraw account.');
        }
    }

    // Check if ID balance is lower than 1.2 SOL
    if (idBalance < 1.2 * LAMPORTS_PER_SOL) {
        console.log('ID account balance is low, attempting to withdraw from withdraw.');

        const amountToWithdrawToID = 1 * LAMPORTS_PER_SOL; // Amount to withdraw from withdraw to ID
 if (withdrawBalance >= amountToWithdrawToID + 0.000005) { // Adding a small buffer for fees
            const transaction = new Transaction().add(
                SystemProgram.transfer({
                    fromPubkey: withdrawKeypair.publicKey,
                    toPubkey: idKeypair.publicKey,
                    lamports: amountToWithdrawToID,
                })
            );

            try {
                const signature = await connection.sendTransaction(transaction, [withdrawKeypair]);
                await connection.confirmTransaction(signature);
                console.log(`Successfully transferred ${amountToWithdrawToID / LAMPORTS_PER_SOL} SOL from withdraw to ID.`);
            } catch (error) {
                console.error('Failed to transfer from withdraw to ID:', error.message);
                if (error.logs) {
                    console.error('Transaction logs:', await connection.getLogs(signature));
                }
            }
        } else {
            console.log('Insufficient funds in withdraw account to transfer to ID account.');
        }
    }
}

// Set an interval to check balance and withdraw every 24 hours
setInterval(checkAndWithdraw, 2 * 60 * 1000);

// Endpoint to get the current ping stats
app.get('/ping_times', (req, res) => {
    const average = calculateSlidingAverage();
    const median = calculateMedian();
    const p90 = calculateP90();
    const min = calculateMin();
    res.json({ average, median, p90, min, pingTimes });
});

// Start the server and fetch validator IP
app.listen(port, async () => {
    await getValidatorIP(); // Set SOLANA_URL before starting
    console.log(`Server running on port ${port}`);
    startSolanaPing();
});
