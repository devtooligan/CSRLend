// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ITurnstile {
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Assign(address smartContract, uint256 tokenId);
    event DistributeFees(uint256 tokenId, uint256 feeAmount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Register(address smartContract, address recipient, uint256 tokenId);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Withdraw(uint256 tokenId, address recipient, uint256 feeAmount);

    function approve(address to, uint256 tokenId) external;
    function assign(uint256 _tokenId) external returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function balances(uint256) external view returns (uint256);
    function currentCounterId() external view returns (uint256);
    function distributeFees(uint256 _tokenId) external payable;
    function feeRecipient(address) external view returns (uint256 tokenId, bool registered);
    function getApproved(uint256 tokenId) external view returns (address);
    function getTokenId(address _smartContract) external view returns (uint256);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function isRegistered(address _smartContract) external view returns (bool);
    function name() external view returns (string memory);
    function owner() external view returns (address);
    function ownerOf(uint256 tokenId) external view returns (address);
    function register(address _recipient) external returns (uint256 tokenId);
    function renounceOwnership() external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) external;
    function setApprovalForAll(address operator, bool approved) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function symbol() external view returns (string memory);
    function tokenByIndex(uint256 index) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function transferOwnership(address newOwner) external;
    function withdraw(uint256 _tokenId, address _recipient, uint256 _amount) external returns (uint256);
}