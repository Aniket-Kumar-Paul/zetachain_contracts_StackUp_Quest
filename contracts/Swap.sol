// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@zetachain/protocol-contracts/contracts/zevm/SystemContract.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/zContract.sol";
import "@zetachain/toolkit/contracts/SwapHelperLib.sol";
import "@zetachain/toolkit/contracts/BytesHelperLib.sol";

contract Swap is zContract {
    SystemContract public immutable systemContract;

    uint256 constant BITCOIN = 18332; // chainID of Bitcoin testnet
    error WrongGasContract();
    error NotEnoughToPayGasFee();

    constructor(address systemContractAddress) {
        systemContract = SystemContract(systemContractAddress);
    }

    modifier onlySystem() {
        require(
            msg.sender == address(systemContract),
            "Only system contract can call this function"
        );
        _;
    }

    // Cross-Chain logic for our smart contract(cross-chain token swap, here)
    // get's called when a user wants to perform a cross-chain swap from an EVM to an EVM address or from Bitcoin to an EVM
    function onCrossChainCall(
        zContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external virtual override onlySystem {
        address targetTokenAddress;
        bytes memory recipientAddress;

        // Get target token address and recipient address from message
        if (context.chainID == BITCOIN) {
            // Call initiated from BITCOIN
            targetTokenAddress = BytesHelperLib.bytesToAddress(message, 0);
            recipientAddress = abi.encodePacked(
                BytesHelperLib.bytesToAddress(message, 20)
            );
        } else {
            // EVM
            (address targetToken, bytes memory recipient) = abi.decode(
                message,
                (address, bytes)
            );
            targetTokenAddress = targetToken;
            recipientAddress = recipient;
        }

        //  swap the tokens - sends the original tokens and receives the swapped ZRC-20 tokens in return
        uint256 outputAmount = SwapHelperLib._doSwap(
            systemContract.wZetaContractAddress(),
            systemContract.uniswapv2FactoryAddress(),
            systemContract.uniswapv2Router02Address(),
            zrc20,
            amount,
            targetTokenAddress,
            0
        );

        // Additional checks are also performed such as checking for gas fees and if there are enough tokens to pay for gas fees, throwing an error if the check fails.
        (address gasZRC20, uint256 gasFee) = IZRC20(targetTokenAddress)
            .withdrawGasFee();

        if (gasZRC20 != targetTokenAddress) revert WrongGasContract();
        if (gasFee >= outputAmount) revert NotEnoughToPayGasFee();

        //  function approves the gas fees payment and sends the remaining swapped tokens to the recipient, completing the cross-chain swap process
        IZRC20(targetTokenAddress).approve(targetTokenAddress, gasFee);
        IZRC20(targetTokenAddress).withdraw(
            recipientAddress,
            outputAmount - gasFee
        );
    }
}
