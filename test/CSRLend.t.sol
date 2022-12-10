// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {Turnstile} from "canto/csr/turnstile.sol";
import {ITurnstile} from "../src/interfaces/ITurnstile.sol";
import {IBorrowerNFT} from "../src/interfaces/IBorrowerNFT.sol";
import {ILenderNFT} from "../src/interfaces/ILenderNFT.sol";

import {CSRLend} from "../src/CSRLend.sol";
import {BorrowerNFT} from "../src/BorrowerNFT.sol";
import {LenderNFT} from "../src/LenderNFT.sol";

contract MockTurnstile is Turnstile {
    function setBalance(uint256 id, uint256 amount) public {
        balances[id] = amount;
    }
}

contract MockRevenueStreamContract {
    MockTurnstile turnstile;

    constructor(Turnstile turnstile_, address csrHolder) {
        turnstile_.register(csrHolder);
    }
}

abstract contract Base is Test {
    CSRLend core;
    MockTurnstile turnstile;
    MockRevenueStreamContract csr1; // may not need this
    MockRevenueStreamContract csr2; // may not need this
    uint256 csrNFTId1;
    uint256 csrNFTId2;

    BorrowerNFT public bnft;
    LenderNFT public lnft;

    address payable borrower = payable(address(0xBADBABE));
    address payable lender1 = payable(address(0xB0B));
    address payable lender2 = payable(address(0xDEADBEEF));

    function setUp() public virtual {
        turnstile = new MockTurnstile();
        vm.deal(address(turnstile), 1_000_000 * 1e18);
        bnft = new BorrowerNFT();
        lnft = new LenderNFT();
        core = new CSRLend(ITurnstile(address(turnstile)), IBorrowerNFT(address(bnft)), ILenderNFT(address(lnft))); // TODO: make params object
        bnft.transferOwnership(address(core));
        lnft.transferOwnership(address(core));
        csr1 = new MockRevenueStreamContract(turnstile, borrower);
        csr2 = new MockRevenueStreamContract(turnstile, borrower);
        csrNFTId1 = turnstile.getTokenId(address(csr1));
        csrNFTId2 = turnstile.getTokenId(address(csr2));
        vm.label(borrower, "borrower");
        vm.deal(borrower, 1_000 * 1e18);
        vm.label(lender1, "lender1");
        vm.deal(lender1, 10_000 * 1e18);
        vm.label(lender2, "lender2");
        vm.deal(lender2, 10_000 * 1e18);
    }
}

contract CSRLendTest__Base is Base {
    function testStartAuction() public {
        uint256 principalAmount = 1000 * 1e18;
        uint256 maxRate = 200;
        assertEq(turnstile.ownerOf(csrNFTId1), borrower);
        vm.startPrank(borrower);
        turnstile.approve(address(core), csrNFTId1);
        core.startAuction(csrNFTId1, principalAmount, maxRate);
        vm.stopPrank();
        CSRLend.Auction memory auction = core.auctions(csrNFTId1);
        CSRLend.Bid memory bid = auction.currentBid;
        assertEq(auction.nftOwner, borrower);
        assertEq(turnstile.ownerOf(csrNFTId1), address(core));
        assertEq(auction.principalAmount, principalAmount);
        assertEq(auction.maxRate, maxRate);
        assertEq(auction.endTime, block.timestamp + 1 days);
        assertEq(bid.bidder, address(0x0));
        assertEq(bid.rate, 0);
    }
}

abstract contract WithAuction is Base {
    uint256 public principalAmount = 1_000 * 1e18;

    function setUp() public virtual override {
        super.setUp();
        uint256 maxRate = 200;
        vm.startPrank(borrower);
        turnstile.approve(address(core), csrNFTId1);
        core.startAuction(csrNFTId1, principalAmount, maxRate);
        vm.stopPrank();
    }
}

contract CSRLendTest__WithAuction is WithAuction {
    function testBid() public {
        uint256 lender1StartingBalance = lender1.balance;
        uint256 coreStartingBalance = address(core).balance;
        uint256 rate = 100;
        vm.prank(lender1);
        core.bid{value: principalAmount}(csrNFTId1, rate);
        CSRLend.Auction memory auction = core.auctions(csrNFTId1);
        CSRLend.Bid memory bid = auction.currentBid;
        assertEq(auction.nftOwner, borrower);
        assertEq(turnstile.ownerOf(csrNFTId1), address(core));
        assertEq(auction.principalAmount, 1000 * 1e18);
        assertEq(auction.maxRate, 200);
        assertEq(auction.endTime, block.timestamp + 1 days);
        assertEq(bid.bidder, lender1);
        assertEq(bid.rate, rate);
        assertEq(lender1.balance, lender1StartingBalance - principalAmount);
        assertEq(address(core).balance, coreStartingBalance + principalAmount);
    }
}

abstract contract WithBid is WithAuction {
    uint256 public rate = 100;

    function setUp() public virtual override {
        super.setUp();
        vm.prank(lender1);
        core.bid{value: principalAmount}(csrNFTId1, rate);
    }
}

contract CSRLendTest__WithBid is WithBid {
    // TODO: Add revert tests for bid and finalize

    function testOverBid() public {
        uint256 lender1StartingBalance = lender1.balance;
        uint256 lender2StartingBalance = lender2.balance;
        uint256 coreStartingBalance = address(core).balance;
        uint256 newRate = 95;
        vm.prank(lender2);
        core.bid{value: principalAmount}(csrNFTId1, newRate);
        CSRLend.Auction memory auction = core.auctions(csrNFTId1);
        CSRLend.Bid memory bid = auction.currentBid;
        assertEq(turnstile.ownerOf(csrNFTId1), address(core));
        assertEq(auction.principalAmount, 1000 * 1e18);
        assertEq(auction.maxRate, 200);
        assertEq(auction.endTime, block.timestamp + 1 days);
        assertEq(bid.bidder, lender2);
        assertEq(bid.rate, newRate);
        assertEq(lender1.balance, lender1StartingBalance + principalAmount);
        assertEq(lender2.balance, lender2StartingBalance - principalAmount);
        assertEq(address(core).balance, coreStartingBalance);
    }

    function testLast15MinuteBid() public {
        // bid in last 15 and see auction extended
        uint256 newRate = 95;
        vm.warp(block.timestamp + 1 days - 15 minutes);
        vm.prank(lender2);
        core.bid{value: principalAmount}(csrNFTId1, newRate);
        CSRLend.Auction memory auction = core.auctions(csrNFTId1);
        assertEq(auction.endTime, block.timestamp + 15 minutes);

        // one more time
        newRate = 93;
        vm.warp(block.timestamp + 10 minutes);
        vm.prank(lender1);
        core.bid{value: principalAmount}(csrNFTId1, newRate);
        auction = core.auctions(csrNFTId1);
        assertEq(auction.endTime, block.timestamp + 15 minutes);

        // too late
        newRate = 91;
        vm.warp(block.timestamp + 16 minutes);
        vm.expectRevert("CSRLend: auction has ended");
        vm.prank(lender1);
        core.bid{value: principalAmount}(csrNFTId1, newRate);
    }

    function testFinalizeAuction() public {
        assertEq(bnft.balanceOf(borrower), 0x0);
        assertEq(lnft.balanceOf(lender1), 0x0);
        uint256 borrowerStartingBalance = borrower.balance;
        uint256 coreStartingBalance = address(core).balance;

        // ffwd time
        vm.warp(block.timestamp + 1 days + 1 seconds);

        vm.prank(address(0x123)); // anyone can call this
        (uint256 bnftId, uint256 lnftId) = core.finalizeAuction(csrNFTId1);

        CSRLend.LoanInfo memory loan = core.loanInfo(bnftId);
        assertEq(loan.balance, principalAmount);
        assertEq(loan.rate, rate);
        assertEq(loan.lastUpdated, block.timestamp);
        assertEq(loan.csrNFTId, csrNFTId1);
        assertEq(loan.lenderNFTId, lnftId);
        assertTrue(loan.status == CSRLend.Status.ACTIVE);
        assertEq(borrower.balance, borrowerStartingBalance + principalAmount);
        assertEq(address(core).balance, coreStartingBalance - principalAmount);
        assertEq(bnft.ownerOf(bnftId), borrower);
        assertEq(lnft.ownerOf(lnftId), lender1);
    }
}

abstract contract WithLoan is WithBid {
    uint256 public bnftId;
    uint256 public lnftId;

    function setUp() public virtual override {
        super.setUp();
        vm.warp(block.timestamp + 1 days + 1 seconds);
        vm.prank(address(0x123)); // anyone can call this
        (bnftId, lnftId) = core.finalizeAuction(csrNFTId1);
    }
}

contract CSRLendTest__WithLoan is WithLoan {
    function testCalculateInterest() public {
        // answer derived on desmos:
        // https://www.desmos.com/calculator/aw7omelxde
        // d = 5,000 // starting debt balance
        // r = 0.067 // interest rate
        // t = 44    // time (days)
        uint256 answer = 5040.51921967840551 * 1e18;
        uint256 debtWithAccrued = core.calculateInterest(5_000 * 1e18, 670, 44 days);
        assertEq(debtWithAccrued, answer);

        // answer derived on desmos:
        // https://www.desmos.com/calculator/aw7omelxde
        // d = 100,000 // starting debt balance
        // r = 0.11 // interest rate
        // t = 301    // time (days)
        answer = 109488.5990477010366 * 1e18;
        debtWithAccrued = core.calculateInterest(100_000 * 1e18, 1100, 301 days);
        assertEq(debtWithAccrued, answer);

        // answer derived on desmos:
        // https://www.desmos.com/calculator/aw7omelxde
        // d = 500 // starting debt balance
        // r = 0.01 // interest rate
        // t = 1    // time (days)
        answer = 500.000136892558096 * 1e18;
        debtWithAccrued = core.calculateInterest(500 * 1e18, 1, 1 days);
        console.log("+ + file: CSRLend.t.sol:225 + testCalculateInterest + debtWithAccrued", debtWithAccrued);
        assertEq(debtWithAccrued, answer);
    }

    function testRepayWithClaimable() public {
        // partial paydown
        CSRLend.LoanInfo memory loan1 = core.loanInfo(bnftId);
        vm.warp(100 days);
        uint256 amount = 600 * 1e18;
        turnstile.setBalance(csrNFTId1, amount);
        uint256 coreStartingBalance = address(core).balance;
        core.repayWithClaimable(bnftId);
        CSRLend.LoanInfo memory loan2 = core.loanInfo(bnftId);
        assertTrue(loan1.balance - loan2.balance < amount); // because interest has accrued
        assertTrue(loan2.status == CSRLend.Status.ACTIVE);
        assertEq(address(core).balance - coreStartingBalance, amount);

        // complete paydown (includes accrued interest)
        vm.warp(100 days);
        amount = 600 * 1e18;
        turnstile.setBalance(csrNFTId1, amount);
        coreStartingBalance = address(core).balance;
        core.repayWithClaimable(bnftId);
        CSRLend.LoanInfo memory loan3 = core.loanInfo(bnftId);
        assertTrue(loan3.status == CSRLend.Status.WITHDRAWABLE);
    }

    function testRepayWithExternal() public {
        // partial paydown
        CSRLend.LoanInfo memory loan1 = core.loanInfo(bnftId);
        vm.warp(100 days);
        uint256 amount = 300 * 1e18;
        vm.deal(borrower, 1000 * 1e18);
        uint256 coreStartingBalance = address(core).balance;
        vm.prank(borrower);
        core.repayWithExternal{value: amount}(bnftId);
        CSRLend.LoanInfo memory loan2 = core.loanInfo(bnftId);
        assertTrue(loan1.balance - loan2.balance < amount); // because interest has accrued
        assertTrue(loan2.status == CSRLend.Status.ACTIVE);
        assertEq(address(core).balance - coreStartingBalance, amount);

        // complete paydown
        amount = 1000 * 1e18;
        vm.deal(borrower, 1000 * 1e18);
        coreStartingBalance = address(core).balance;
        vm.prank(borrower);
        core.repayWithExternal{value: amount}(bnftId);
        CSRLend.LoanInfo memory loan3 = core.loanInfo(bnftId);
        assertEq(loan3.balance, 0); // because interest has accrued
        assertTrue(loan3.status == CSRLend.Status.WITHDRAWABLE);
        assertTrue(address(core).balance - coreStartingBalance < amount); // because it was more than enough
    }

    function testWithdrawPayable() public {
        // partial paydown by borrower
        CSRLend.LoanInfo memory loan1 = core.loanInfo(bnftId);
        vm.warp(100 days);
        uint256 amount = 300 * 1e18;
        vm.deal(borrower, 1000 * 1e18);
        uint256 coreStartingBalance = address(core).balance;
        vm.prank(borrower);
        core.repayWithExternal{value: amount}(bnftId);

        // lender partially withdraws payable
        uint256 coreBalance = address(core).balance;
        vm.prank(lender1);
        core.withdrawPayable(lnftId, 1e18);
        assertEq(address(core).balance, coreBalance - 1e18);
        assertEq(lnft.balanceOf(lender1), 1);

        // lender withdraws all payable by passing 0 for amount
        coreBalance = address(core).balance;
        vm.prank(lender1);
        core.withdrawPayable(lnftId, 0);
        CSRLend.LoanInfo memory loan = core.loanInfo(bnftId);
        assertTrue(loan.status == CSRLend.Status.ACTIVE);
        assertEq(lnft.balanceOf(lender1), 1);
    }
}

abstract contract WithRepaidLoan is WithLoan {
    function setUp() public virtual override {
        super.setUp();
        vm.warp(100 days);
        uint256 amount = 1500 * 1e18;
        vm.deal(borrower, amount + 1000 * 1e18);
        vm.prank(borrower);
        core.repayWithExternal{value: amount}(bnftId);
        CSRLend.LoanInfo memory loan = core.loanInfo(bnftId);
        assertEq(loan.balance, 0); // because interest has accrued
        assertTrue(loan.status == CSRLend.Status.WITHDRAWABLE);
    }
}

contract CSRLendTest__WithRepaidLoan is WithRepaidLoan {
    function testWithdrawNFT() public {
        assertEq(turnstile.ownerOf(csrNFTId1), address(core));
        assertEq(bnft.balanceOf(borrower), 1);
        assertEq(bnft.ownerOf(bnftId), borrower);
        vm.prank(borrower);
        core.withdrawNFT(bnftId);
        assertEq(turnstile.ownerOf(csrNFTId1), borrower);
        assertEq(bnft.balanceOf(borrower), 0);
        assertTrue(core.loanInfo(bnftId).status == CSRLend.Status.CLOSED);
    }

    function testWithDrawPayableAndBurnBothNFTs() public {
        // lender partially withdraws payable
        uint256 coreBalance = address(core).balance;
        vm.prank(lender1);
        core.withdrawPayable(lnftId, 1e18);
        assertEq(address(core).balance, coreBalance - 1e18);
        assertEq(lnft.balanceOf(lender1), 1);
        CSRLend.LoanInfo memory loan = core.loanInfo(bnftId);
        assertTrue(loan.status == CSRLend.Status.WITHDRAWABLE);

        // lender withdraws all payable by passing 0 for amount.  since loan is
        // paid off and in WITHDRAWABLE state, the borrower NFT is burned
        coreBalance = address(core).balance;
        vm.prank(lender1);
        core.withdrawPayable(lnftId, 0);
        loan = core.loanInfo(bnftId);
        assertTrue(loan.status == CSRLend.Status.WITHDRAWABLE);
        assertEq(lnft.balanceOf(lender1), 0); // BURNED

        // borrower withdraws csrNFT and this closes loan and burns the borrower NFT
        vm.prank(borrower);
        core.withdrawNFT(bnftId);
        assertEq(turnstile.ownerOf(csrNFTId1), borrower);
        assertEq(bnft.balanceOf(borrower), 0);
        assertTrue(core.loanInfo(bnftId).status == CSRLend.Status.CLOSED);
    }
}
