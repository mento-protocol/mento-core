# Trove Management System

A modern web interface for managing troves in the Bold Protocol system. This application allows users to:

- Connect their MetaMask wallet
- Open new troves with custom collateral and debt amounts
- Redeem collateral by burning BOLD tokens
- View and manage existing troves
- Update price feed information
- Monitor trove health and liquidation status

## Prerequisites

- Node.js (v14 or higher)
- MetaMask browser extension
- Access to the Bold Protocol smart contracts

## Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   npm install
   ```

## Configuration

Before running the application, you need to update the contract addresses in `src/context/Web3Context.tsx`:

- `troveManagerAddress`
- `borrowerOperationsAddress`
- `collateralRegistryAddress`
- `priceFeedAddress`

## Running the Application

1. Start the development server:

   ```bash
   npm start
   ```

2. Open [http://localhost:3000](http://localhost:3000) in your browser

3. Connect your MetaMask wallet to interact with the application

## Features

- **Wallet Connection**: Seamlessly connect your MetaMask wallet
- **Trove Management**: Open, close, and monitor troves
- **Collateral Redemption**: Redeem collateral by burning BOLD tokens
- **Price Feed Updates**: Update and monitor price feed information
- **Real-time Updates**: View trove status and health metrics in real-time

## Security Considerations

- Always verify transaction details before confirming
- Keep your MetaMask wallet secure
- Never share your private keys or seed phrases
- Be cautious when approving token allowances

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request
