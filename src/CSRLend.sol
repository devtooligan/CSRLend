// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IBorrowerNFT} from "./interfaces/IBorrowerNFT.sol";
import {ITurnstile} from "./interfaces/ITurnstile.sol";
import {ILenderNFT} from "./interfaces/ILenderNFT.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ABDKMath64x64} from "abdk/ABDKMath64x64.sol";

/**
 *   ,ad8888ba,    ad88888ba   88888888ba   88                                            88
 *  d8"'    `"8b  d8"     "8b  88      "8b  88                                            88
 * d8'            Y8,          88      ,8P  88                                            88
 * 88             `Y8aaaaa,    88aaaaaa8P'  88           ,adPPYba,  8b,dPPYba,    ,adPPYb,88
 * 88               `"""""8b,  88""""88'    88          a8P_____88  88P'   `"8a  a8"    `Y88
 * Y8,                    `8b  88    `8b    88          8PP"""""""  88       88  8b       88
 *  Y8a.    .a8P  Y8a     a8P  88     `8b   88          "8b,   ,aa  88       88  "8a,   ,d88
 *   `"Y8888Y"'    "Y88888P"   88      `8b  88888888888  `"Ybbd8"'  88       88   `"8bbdP"Y8
 *
 *                                                                            Built on Canto
 */

/// @notice A protocol for borrowing against Contract Secured Revenue NFTs.
contract CSRLend {
    using SafeTransferLib for address payable;
    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint256;

    /* EVENTS
    **************************************************************************************************************************/

    event CantoReceived(address indexed from, uint256 amount);
    event AuctionStarted(uint256 indexed csrNFTId, uint256 principalAmount, uint256 maxRate, uint256 endTime);
    event NewBid(uint256 indexed csrNFTId, address indexed bidder, uint256 rate);
    event NewLoan(
        uint256 indexed csrNFTId,
        uint256 indexed borrowerNFTId,
        uint256 indexed lenderNFTId,
        uint256 principalAmount,
        uint256 rate
    );
    event LoanPaid(uint256 indexed borrowerNFTId, uint256 amount, uint256 newBalance);
    event InterestAccrued(uint256 indexed borrowerNFTId, uint256 interestAmount, uint256 newBalance);
    event PayableWithdrawn(uint256 indexed lenderNFTId, address indexed to, uint256 amount, uint256 remainingPayable);
    event LoanClosed(uint256 indexed borrowerNFTId);

    /* STRUCTS AND ENUMS
    **************************************************************************************************************************/

    /// @param ACTIVE The loan is active and still has an outstanding balance.
    /// @param WITHDRAWABLE The loan is paid off, but the csrNFT has not been withdrawn.
    /// @param CLOSED The the csrNFT has been withdrawn. There may be a payable amount owed to lender.
    enum Status {
        ACTIVE,
        WITHDRAWABLE,
        CLOSED
    }

    // @param bidder Address of the bidder.
    // @param rate Interest rate where 1 unit is 10 bps (0.1%) so a value of 95 is 9.5%.
    struct Bid {
        address bidder;
        uint256 rate;
    }

    /// @param nftOwner Address of the owner of the csrNFT.
    /// @param principalAmount Amount of Canto to borrow in wei (fp18).
    /// @param maxRate 1 unit is 10 bps (0.1%) so a value of 95 is 9.5%.
    /// @param endTime Timestamp of the end of the auction.  Auctions are 1 day long but are extended
    /// by 15 minutes every time a new bid is placed in the last 15 minutes.
    /// @param currentBid The current best bid, contains bidder and rate.
    struct Auction {
        address nftOwner;
        uint256 principalAmount;
        uint256 maxRate;
        uint256 endTime;
        Bid currentBid;
    }

    /// @param balance Amount of Canto borrowed in wei (fp18).
    /// @param rate Interest rate where 1 unit is 10 bps (0.1%) so a value of 95 is 9.5%.
    /// @param lastUpdated Timestamp of the last time the accrued interest was computed.
    /// @param csrNFTId The tokenId of the csrNFT.
    /// @param lenderNFTId The tokenId of the lenderNFT.
    /// @param status The status of the loan (ACTIVE, WITHDRAWABLE, CLOSED).
    struct LoanInfo {
        uint256 balance;
        uint256 rate;
        uint256 lastUpdated;
        uint256 csrNFTId;
        uint256 lenderNFTId;
        Status status;
    }

    /// @param amount Amount of Canto owed to the lender in wei (fp18).  This represents amounts that
    /// have been claimed or paid by the borrower to pay down the loan, but not yet withdrawn from this
    /// contract by the lender.
    /// @param borrowerNFTId The tokenId of the borrowerNFT for reference..
    struct PayableInfo {
        uint256 payableAmount;
        uint256 borrowerNFTId;
    }

    /* IMMUTABLES
    **************************************************************************************************************************/

    IBorrowerNFT public immutable borrowerNFT;
    ILenderNFT public immutable lenderNFT;
    ITurnstile public immutable turnstile;
    uint256 internal constant SECONDS_IN_A_YEAR = 31536000;

    /* STORAGE
    **************************************************************************************************************************/

    /// @dev mapping of csrNFTId to Auction info.
    mapping(uint256 => Auction) internal _auctions;

    // @dev mapping of borrowerNFTId to Loan info.
    mapping(uint256 => LoanInfo) internal _loanInfo;

    /// @dev mapping of LenderNFT tokenId to Payable info.
    mapping(uint256 => PayableInfo) internal _payableInfo;

    /* CONSTRUCTOR
    **************************************************************************************************************************/

    constructor(ITurnstile turnstile_, IBorrowerNFT borrowerNFT_, ILenderNFT lenderNFT_) {
        turnstile = turnstile_;
        borrowerNFT = borrowerNFT_;
        lenderNFT = lenderNFT_;
    }

    receive() external payable {
        emit CantoReceived(msg.sender, msg.value);
    }

    /* AUCTION FUNCTIONS
    **************************************************************************************************************************/

    /// @notice Starts an auction for the csrNFT.
    /// @param csrNFTId The tokenId of the csrNFT.
    /// @param principalAmount Amount of Canto to borrow in wei (fp18).
    /// @param maxRate 1 unit is 10 bps (0.1%) so a value of 95 is 9.5%.
    function startAuction(uint256 csrNFTId, uint256 principalAmount, uint256 maxRate) public {
        require(turnstile.ownerOf(csrNFTId) == msg.sender, "CSRLend: caller is not the owner of the NFT");
        require(principalAmount > 0, "CSRLend: principalAmount must be greater than 0");

        uint256 endTime = block.timestamp + 1 days;
        _auctions[csrNFTId] = Auction(msg.sender, principalAmount, maxRate, endTime, Bid(address(0), 0));
        turnstile.safeTransferFrom(msg.sender, address(this), csrNFTId);

        emit AuctionStarted(csrNFTId, principalAmount, maxRate, endTime);
    }

    /// @notice Places a bid on an auction.
    /// @dev Principal amount must be transferred when calling this fn.
    /// @param csrNFTId The tokenId of the csrNFT.
    /// @param rate Interest rate where 1 unit is 10 bps (0.1%) so a value of 95 is 9.5%.
    function bid(uint256 csrNFTId, uint256 rate) public payable {
        Auction memory auction = _auctions[csrNFTId]; // cache to save gas
        Bid memory priorBid = auction.currentBid;
        require(auction.principalAmount > 0, "CSRLend: auction does not exist");
        require(msg.value == auction.principalAmount, "CSRLend: msg.value must equal principalAmount");
        require(auction.endTime > block.timestamp, "CSRLend: auction has ended");
        require(rate <= auction.maxRate, "CSRLend: rate must be less than or equal to maxRate");
        // The value of currentBid.bidder will be address(0x0) when there is no current bid.
        require(rate < priorBid.rate || priorBid.bidder == address(0x0), "CSRLend: rate must be less than current bid");

        // Update the current bid.
        _auctions[csrNFTId].currentBid = Bid(msg.sender, rate);

        // If a bid is received in the last 15 minutes of the auction, extend the auction by 15 minutes.
        if (auction.endTime - block.timestamp <= 15 minutes) {
            _auctions[csrNFTId].endTime = block.timestamp + 15 minutes;
        }

        // Refund previous bidder.
        if (priorBid.bidder != address(0x0)) {
            payable(priorBid.bidder).safeTransferETH(auction.principalAmount);
        }

        emit NewBid(csrNFTId, msg.sender, rate);
    }

    /// @notice If winning bid, mints borrowerNFT and lenderNFT and transfers principal amount.
    /// @param csrNFTId The tokenId of the csrNFT.
    /// @return borrowerNFTId The tokenId of the newly minted borrowerNFT. Returns 0x0 if no winner.
    /// @return lenderNFTId The tokenId of the newly minted lender NFT. Returns 0x0 if no winner.
    function finalizeAuction(uint256 csrNFTId) public returns (uint256 borrowerNFTId, uint256 lenderNFTId) {
        Auction memory auction = _auctions[csrNFTId];
        require(_auctions[csrNFTId].principalAmount > 0, "CSRLend: auction does not exist");
        require(_auctions[csrNFTId].endTime <= block.timestamp, "CSRLend: auction has not ended");

        // In any case, delete the auction.
        _deleteAuction(csrNFTId);

        // If there is no bid, the auction is canceled and the NFT is returned to the owner.
        Bid memory currentBid = auction.currentBid;
        if (currentBid.bidder == address(0x0)) {
            turnstile.safeTransferFrom(address(this), auction.nftOwner, csrNFTId);
            return (0x0, 0x0);
        }

        // Mint NFT for borrower and lender.
        borrowerNFTId = borrowerNFT.safeMint(auction.nftOwner);
        lenderNFTId = lenderNFT.safeMint(currentBid.bidder);

        // Create the loan.
        _loanInfo[borrowerNFTId] =
            LoanInfo(auction.principalAmount, currentBid.rate, block.timestamp, csrNFTId, lenderNFTId, Status.ACTIVE);
        _payableInfo[lenderNFTId] = PayableInfo(0, borrowerNFTId);

        // Transfer principal to borrower.
        payable(auction.nftOwner).safeTransferETH(auction.principalAmount);

        emit NewLoan(csrNFTId, borrowerNFTId, lenderNFTId, auction.principalAmount, currentBid.rate);
    }

    /// @param csrNFTId The tokenId of the csrNFT.
    function _deleteAuction(uint256 csrNFTId) internal {
        delete _auctions[csrNFTId].currentBid;
        delete _auctions[csrNFTId];
    }

    /* REPAYMENT FUNCTIONS
    **************************************************************************************************************************/

    /// @dev Pay down loan by withdrawing on the CSR.
    /// @param borrowerNFTId The tokenId of the borrowerNFT.
    function repayWithClaimable(uint256 borrowerNFTId) external {
        require(_loanInfo[borrowerNFTId].balance > 0, "CSRLend: no balance to repay");

        _accrueInterest(borrowerNFTId);
        LoanInfo memory loan = _loanInfo[borrowerNFTId];

        // Determine the amount to withdraw.
        uint256 claimableAmount = turnstile.balances(loan.csrNFTId);
        uint256 amount = _min(loan.balance, claimableAmount);

        // Update the outstanding debt balance.
        uint256 newBalance = _loanInfo[borrowerNFTId].balance = loan.balance - amount;
        if (newBalance == 0) {
            _loanInfo[borrowerNFTId].status = Status.WITHDRAWABLE;
        }

        // Update the payable balance.
        _payableInfo[loan.lenderNFTId].payableAmount += amount;
        // Withdraw funds to this contract.
        turnstile.withdraw(loan.csrNFTId, payable(address(this)), amount);

        emit LoanPaid(borrowerNFTId, amount, newBalance);
    }

    /// @dev Pay down loan by sending Canto to this contract.
    /// @param borrowerNFTId The tokenId of the borrowerNFT.
    function repayWithExternal(uint256 borrowerNFTId) external payable {
        require(_loanInfo[borrowerNFTId].balance > 0, "CSRLend: no balance to repay");
        require(msg.value > 0, "CSRLend: msg.value must be greater than 0");
        _accrueInterest(borrowerNFTId);
        LoanInfo memory loan = _loanInfo[borrowerNFTId];

        // Determine the amount to repay.
        uint256 amount = _min(loan.balance, msg.value);

        // Update the outstanding debt balance.
        uint256 newBalance = _loanInfo[borrowerNFTId].balance = loan.balance - amount;
        if (newBalance == 0) {
            _loanInfo[borrowerNFTId].status = Status.WITHDRAWABLE;
        }

        // Update the payable balance.
        _payableInfo[loan.lenderNFTId].payableAmount += amount;

        // Refund the excess.
        if (msg.value > amount) {
            payable(msg.sender).safeTransferETH(msg.value - amount);
        }

        emit LoanPaid(borrowerNFTId, amount, newBalance);
    }

    /// @param borrowerNFTId The tokenId of the borrowerNFT.
    function _accrueInterest(uint256 borrowerNFTId) internal {
        LoanInfo memory loan = _loanInfo[borrowerNFTId];
        uint256 secondsSinceLastUpdated = block.timestamp - loan.lastUpdated;
        uint256 newBalance = calculateInterest(loan.balance, loan.rate, secondsSinceLastUpdated);
        _loanInfo[borrowerNFTId].balance = newBalance;
        emit InterestAccrued(borrowerNFTId, newBalance - loan.balance, newBalance);
    }

    /* WITHDRAW FUNCTIONS
    **************************************************************************************************************************/

    /// @notice Draw down the borrowerNFT holder's payable balance.
    /// @param lenderNFTId The borrowerNFT id.
    /// @param amount The amount to withdraw.  If 0, withdraw the entire balance.
    function withdrawPayable(uint256 lenderNFTId, uint256 amount) external {
        require(msg.sender == lenderNFT.ownerOf(lenderNFTId), "CSRLend: caller is not the owner of the NFT");

        // Determine amount to withdraw.
        PayableInfo memory lenderInfo = _payableInfo[lenderNFTId];
        uint256 withdrawAmount;
        if (amount == 0) {
            // If amount is 0, withdraw the entire balance.
            withdrawAmount = lenderInfo.payableAmount;
        } else {
            // Otherwise withdraw the amount up to the payable balance.
            withdrawAmount = _min(lenderInfo.payableAmount, amount);
        }

        // Update the payable balance.
        uint256 remainingPayable = _payableInfo[lenderNFTId].payableAmount = lenderInfo.payableAmount - withdrawAmount;

        // Transfer the funds.
        payable(msg.sender).safeTransferETH(withdrawAmount);

        // Burn the lenderNFT if the loan is paid off complete.
        Status status = _loanInfo[lenderInfo.borrowerNFTId].status;
        if (remainingPayable == 0 && (status == Status.WITHDRAWABLE || status == Status.CLOSED)) {
            lenderNFT.burn(lenderNFTId);
        }

        emit PayableWithdrawn(lenderNFTId, msg.sender, withdrawAmount, remainingPayable);
    }

    /// @notice Withdraw the csrNFT and close a loan.
    /// @param borrowerNFTId The borrowerNFT id.
    function withdrawNFT(uint256 borrowerNFTId) external {
        LoanInfo memory loan = _loanInfo[borrowerNFTId];
        require(msg.sender == borrowerNFT.ownerOf(borrowerNFTId), "CSRLend: caller not owner of BorrowerNFT");
        require(loan.status == Status.WITHDRAWABLE, "CSRLend: csrNFT must be WITHDRAWABLE");

        // Mark loan as CLOSED.
        _loanInfo[borrowerNFTId].status = Status.CLOSED;

        // Burn the borrowerNFT
        borrowerNFT.burn(borrowerNFTId);

        // Transfer the csrNFT.
        turnstile.safeTransferFrom(address(this), msg.sender, loan.csrNFTId);

        emit LoanClosed(borrowerNFTId);
    }

    /* VIEW FUNCTIONS
    **************************************************************************************************************************/

    function auctions(uint256 csrNFTId) external view returns (Auction memory) {
        return _auctions[csrNFTId];
    }

    function loanInfo(uint256 borrowerNFTId) external view returns (LoanInfo memory) {
        return _loanInfo[borrowerNFTId];
    }

    function payableInfo(uint256 lenderNFTId) external view returns (PayableInfo memory) {
        return _payableInfo[lenderNFTId];
    }

    /* UTILITY AND MISC FUNCTIONS
    **************************************************************************************************************************/

    function onERC721Received(address, address, uint256, bytes calldata) external virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice Calculates the interest accrued on a loan.
    /// @dev Uses ABDKMath64x64 library and limits to 18 decimals of precision.
    function calculateInterest(uint256 balance, uint256 rate, uint256 timeElapsed) public pure returns (uint256) {
        uint256 precision = 1e18;

        // debtMultiplier = exp(rate * daysElapsed / 365.25 / 1000) * 1e18 (18 decimals of precision)
        uint256 debtMultiplier = rate.fromUInt().mul((timeElapsed / 1 days).fromUInt()).div(uint256(3652500).fromUInt())
            .exp().mul(uint256(precision).fromUInt()).toUInt();
        return balance * debtMultiplier / 1e18;
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }
}
