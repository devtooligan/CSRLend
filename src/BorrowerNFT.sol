// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "solmate/tokens/ERC721.sol";
import "openzeppelin/access/Ownable.sol";

/**

88888888ba
88      "8b
88      ,8P
88aaaaaa8P'   ,adPPYba,   8b,dPPYba,  8b,dPPYba,   ,adPPYba,   8b      db      d8   ,adPPYba,  8b,dPPYba,
88""""""8b,  a8"     "8a  88P'   "Y8  88P'   "Y8  a8"     "8a  `8b    d88b    d8'  a8P_____88  88P'   "Y8
88      `8b  8b       d8  88          88          8b       d8   `8b  d8'`8b  d8'   8PP"""""""  88
88      a8P  "8a,   ,a8"  88          88          "8a,   ,a8"    `8bd8'  `8bd8'    "8b,   ,aa  88
88888888P"    `"YbbdP"'   88          88           `"YbbdP"'       YP      YP       `"Ybbd8"'  88   N F T
*/

/// @notice For use with CSRLend Protocol.  This NFT is issued to the borrower when a loan is created.
/// It is burned once the loan is repaid and the borrower has received their csrNFT back.
contract BorrowerNFT is Ownable, ERC721 {
    uint256 public currentTokenId;

    constructor() ERC721("CSRLend BorrowerNFT", "CSRL-B") {}

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
