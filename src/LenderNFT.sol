// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "solmate/tokens/ERC721.sol";
import "openzeppelin/access/Ownable.sol";

/**

88                                            88
88                                            88
88                                            88
88           ,adPPYba,  8b,dPPYba,    ,adPPYb,88   ,adPPYba,  8b,dPPYba,
88          a8P_____88  88P'   `"8a  a8"    `Y88  a8P_____88  88P'   "Y8
88          8PP"""""""  88       88  8b       88  8PP"""""""  88
88          "8b,   ,aa  88       88  "8a,   ,d88  "8b,   ,aa  88
88888888888  `"Ybbd8"'  88       88   `"8bbdP"Y8   `"Ybbd8"'  88     N F T
 */

/// @notice For use with CSRLend Protocol.  This NFT is issued to the lender when a loan is created.
/// Owner of this NFT is entitled to the CSR revenue stream until the loan is repaid.
/// It is burned once the loan is repaid and the lender has withdrawn all payable amounts.
contract LenderNFT is Ownable, ERC721 {
    uint256 public currentTokenId;

    constructor() ERC721("CSRLend LenderNFT", "CSRL-L") {}

    function tokenURI(uint256) public pure virtual override returns (string memory) {
        // TODO: Design cool looking NFT.
    }

    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

    function safeMint(address to) external onlyOwner returns (uint256 newTokenId) {
        newTokenId = currentTokenId++;
        _safeMint(to, newTokenId);
    }
}
