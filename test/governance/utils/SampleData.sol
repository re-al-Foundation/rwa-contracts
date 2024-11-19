// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @dev This contract just duplicates all delegated tokenIds into a public array to be used for integration tests.
contract SampleData {
    uint256[] public sampleDataSet;
    mapping(uint256 tokenId => address delegator) public getDelegatorFromToken;

    constructor() {
        sampleDataSet.push(3074);
        getDelegatorFromToken[3074] = 0xa06F6d30d23AcF3a25438ef9c839A4da3c690003;

        sampleDataSet.push(3075);
        getDelegatorFromToken[3075] = 0xeDf4feDaBf5ed47ad418b4aB6BeA1a3a677CB01D;

        sampleDataSet.push(3076);
        getDelegatorFromToken[3076] = 0x1D5F84A07bf45e032fA16BE71078F5048a899d89;

        sampleDataSet.push(3077);
        getDelegatorFromToken[3077] = 0x34575DB3e9db508f5D2513036ea272FE35C0d173;

        sampleDataSet.push(3078);
        getDelegatorFromToken[3078] = 0x34848FDf31F52f1968FdD92A98556531065a8B6F;

        sampleDataSet.push(3079);
        getDelegatorFromToken[3079] = 0x47EcCAb31417696BCdDfDD4D62c82337D91f21a7;

        sampleDataSet.push(3080);
        getDelegatorFromToken[3080] = 0xB196BE4DbD37A6aE768bD11ADa3B2466fdFa5F49;

        sampleDataSet.push(3081);
        getDelegatorFromToken[3081] = 0x22646Ec608698F34E9a277E793dc3c0e225cA5aD;

        sampleDataSet.push(3082);
        getDelegatorFromToken[3082] = 0x7CA4011534bC8E32Cfb9Ff983D2c8d5c4f5Cd910;

        sampleDataSet.push(3083);
        getDelegatorFromToken[3083] = 0x183Cf891700b1B17ff9eb97770a592130b027a06;
    }

    function getSampleDataSet() public view returns (uint256[] memory) {
        return sampleDataSet;
    }
}