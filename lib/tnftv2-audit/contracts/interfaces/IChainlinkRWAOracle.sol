// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

interface IChainlinkRWAOracle {
    struct Data {
        uint256 fingerprint;
        uint256 weSellAt;
        uint256 lockedAmount;
        uint256 weSellAtStock;
        uint16 currency;
        uint16 location;
        uint256 timestamp;
    }

    function fingerprints(uint256 index) external view returns (uint256 fingerprint);

    function getFingerprintsAll() external view returns (uint256[] memory fingerprints);

    function getFingerprintsLength() external view returns (uint256 length);

    function fingerprintData(uint256 fingerprint) external view returns (Data memory data);

    function lastUpdateTime() external view returns (uint256 timestamp);

    function updateInterval() external view returns (uint256 secondsInterval);

    function oracleDataAll() external view returns (Data[] memory);

    function oracleDataBatch(uint256[] calldata fingerprints) external view returns (Data[] memory);

    function getDecimals() external view returns (uint8 decimals);

    function decrementStock(uint256 fingerprint) external;

    function latestPrices() external view returns (uint256 latestUpdate);

    function fingerprintExists(uint256 fingerprint) external view returns (bool);
}
