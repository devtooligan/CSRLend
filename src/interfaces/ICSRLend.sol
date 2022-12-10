// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICSRLend {
    event AuctionStarted(uint256 indexed csrNFTId, uint256 principalAmount, uint256 maxRate, uint256 endTime);
    event CantoReceived(address indexed from, uint256 amount);
    event InterestAccrued(uint256 indexed borrowerNFTId, uint256 interestAmount, uint256 newBalance);
    event LoanClosed(uint256 indexed borrowerNFTId);
    event LoanPaid(uint256 indexed borrowerNFTId, uint256 amount, uint256 newBalance);
    event NewBid(uint256 indexed csrNFTId, address indexed bidder, uint256 rate);
    event NewLoan(
        uint256 indexed csrNFTId,
        uint256 indexed borrowerNFTId,
        uint256 indexed lenderNFTId,
        uint256 principalAmount,
        uint256 rate
    );
    event PayableWithdrawn(uint256 indexed lenderNFTId, address indexed to, uint256 amount, uint256 remainingPayable);

    struct Auction {
        address nftOwner;
        uint256 principalAmount;
        uint256 maxRate;
        uint256 endTime;
        Bid currentBid;
    }

    struct Bid {
        address bidder;
        uint256 rate;
    }

    struct LoanInfo {
        uint256 balance;
        uint256 rate;
        uint256 lastUpdated;
        uint256 csrNFTId;
        uint256 lenderNFTId;
        uint8 status;
    }

    struct PayableInfo {
        uint256 payableAmount;
        uint256 borrowerNFTId;
    }

    function activeLoans(uint256 csrNFTId) external view returns (uint256);
    function auctions(uint256 csrNFTId) external view returns (Auction memory);
    function bid(uint256 csrNFTId, uint256 rate) external payable;
    function borrowerNFT() external view returns (address);
    function calculateInterest(uint256 balance, uint256 rate, uint256 timeElapsed) external pure returns (uint256);
    function finalizeAuction(uint256 csrNFTId) external returns (uint256 borrowerNFTId, uint256 lenderNFTId);
    function lenderNFT() external view returns (address);
    function loanInfo(uint256 borrowerNFTId) external view returns (LoanInfo memory);
    function onERC721Received(address, address, uint256, bytes memory) external returns (bytes4);
    function payableInfo(uint256 lenderNFTId) external view returns (PayableInfo memory);
    function repayWithClaimable(uint256 borrowerNFTId) external;
    function repayWithExternal(uint256 borrowerNFTId) external payable;
    function startAuction(uint256 csrNFTId, uint256 principalAmount, uint256 maxRate) external;
    function turnstile() external view returns (address);
    function withdrawNFT(uint256 borrowerNFTId) external;
    function withdrawPayable(uint256 lenderNFTId, uint256 amount) external;
}