# CSRLend Protocol
Protocol for borrowing and lending against Contract Secured Revenue NFTs on the Canto blockchain.

### Setup

```sh
git clone git@github.com:devtooligan/CSRLend.git
cd CSRLend
forge install
```

### Run Tests

```sh
forge test
```

### Deployment

1. Prerequisites: This protocol is designed to work with a pre-existing CSR NFTcontract (turnstile) that has registered smart contracts.
2. Deploy `BorrowerNFT.sol`, no constructor args needed. This and `LenderNFT` are the NFTs given to borrowers and lenders within the CSRLend protocol.
3. Deploy `LenderNFT.sol`, no constructor args needed.
3. Deploy the core contract, `CSRLend.sol` with the constructor args: addresses of the deployed turnstile, BorrowerNFT, and LenderNFT contracts.

```solidity
    constructor(Turnstile turnstile_, BorrowerNFT borrowerNFT_, LenderNFT lenderNFT_) {
        turnstile = turnstile_;
        borrowerNFT = borrowerNFT_;
        lenderNFT = lenderNFT_;
    }
```

### Usage

#### Auction
Use `startAuction()` to initiate an auction on a CSR NFT that you own and select the desired `principalAmount` and `maxRate`.  The NFT will be transferred to the protocol. The duration of the auction is 24 hours but may be extended as described below.

Bidders `bid()` with a lower rate than the current bid.  The principal amount is transferred to the protocol with the bid.  Any bids that come in during the last 15 minutes of the auction will automatically extend the auction 15 minutes.

#### New Loan
If there is a bid when the auction time expires, then a new loan will be created.
  - A `BorrowerNFT` is minted to the borrower.  This NFT entitles the holder to receive the `csrNFT` after the loan is paid off.  Once the loan is paid off and the `csrNFT` is withdrawn, this NFT is burned.
  - A `LenderNFT` is minted to the lender.  This entitles the holder to repayments made on the loan. Repayments are held by the protocol as `payable` until the holder of this NFT chooses to withdraw them.  Once the loan is paid off and all payables are withdrawn, this NFT is burned.

#### Repayment
Repayment can be made by anyone in two ways:

1. `repayWithClaimable` calls `withdraw` on the CSR contract and transfers those funds to the protocol to pay down the loan.
2. `repayWithExternal` can be used along with a transfer into the protocol to directly pay down the loan.

#### Withdraw

- `withdrawPayable` is the function that a holder of a `LenderNFT` can call to receive funds owed from loan repayment.

- `withdrawNFT` is the function called by the holder of a `BorrowerNFT` to receive back the `csrNFT` once the loan is paid off.


### Architectural Decisions

Due to the complexity and uniqueness of the protocol, the initial design has been optimized for `security`, `readability` and `simplicity`.  It has _not_ been optimized for runtime gas. There is significant work that can be done that could reduce the gas usage by as much as 70-80%.  More details about this in the section below.

ABDK 64x64 math library was used to achieve full precision on the interest rate calculations. The 64bit numbers were limited to 18 digits of precision to prevent overflow on larger values.  The interest formula was modeled in [Desmos](https://www.desmos.com/calculator/aw7omelxde) and the results were compared to the results of the Solidity functions using Foundry tests.

### Divergence from Spec

For the most part, the spec was followed exactly, including logic and function names.  The spec assumes there will be an "object" for each loan, borrowerNFT, and lenderNFT, but in actuality these are managed by a single smart contract as is the norm.  Therefore, in addition to the parameters noted in the spec, often a tokenId will need to be provided as well -- borrowerNFT id, lenderNFT id, or csrNFT id depending on the function.

Another divergence from the spec was with regards to the `withdrawable` boolean suggested.  Rather than using this boolean, the following enum was used for a `status` field.  This allows for greater expressiveness and more security.

```solidity
    /// @param ACTIVE The loan is active and still has an outstanding balance.
    /// @param WITHDRAWABLE The loan is paid off, but the csrNFT has not been withdrawn.
    /// @param CLOSED The the csrNFT has been withdrawn. There may be a payable amount owed to lender.
    enum Status {
        ACTIVE,
        WITHDRAWABLE,
        CLOSED
    }
```

The spec describes burning both the `BorrowerNFT` and the `LenderNFT` upon full loan repayment.  However, this does not handle the case where there are still outstanding `payable` amounts owed to the `LenderNFT` holder.  Therefore, logic was written that does not burn the `LenderNFT` token until such time as the loan has been paid off and the payable amounts have been completely withdrawn.

One last comment, the term `payable` is a reserved word in Solidity, so it might be a good idea to use a different term in the next iteration.

### Future Direction

The `BorrowerNFT` and `LenderNFT` contracts are very light.  There is a lot of work that can be done to these including adding metadata about the loan.  One simple way this could be implemented is by having the contracts call the core contract to get updates on the outstanding balance, status, as well as other static data.  It would be fun to design a graphical representation of this data similar to UniswapV3 LP NFTs.

The tests should be finished, to a minimum of 100% test coverage.  Currently untested areas include events, all reverting paths, and other edge cases.

Custom Errors can be implemented optionally. There is debate within the Solidity community as to their merit and `require` with reason strings were used in this codebase.

Here are some specific ideas to optimize gas:
 - Structs can be much more tightly packed.  In the current version every item in a struct is a full 256 bit whereas in many cases even a 32bit type would suffice.
 - Certain mappings can be combined or removed all together.  If we wanted to store a lot of data off-chain then even more can be removed.  For example, there is currently a mapping of `borrowerNFTId` to `LoanInfo` as well as a mapping of `csrNFTId` to `borrowerNFTId` which is used to determine active loans. These two could be merged into a single mapping and an active loan could be inferred by its inclusion in the new mapping.
 - We could probably do away with the `status` field on the loan altogether as the status can be computed based on comparisons with other fields.

 Implementing these solutions suggested above would offer a significant savings but it does come with some added complexity and risk.

