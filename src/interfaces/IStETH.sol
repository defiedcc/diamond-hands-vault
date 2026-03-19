// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

interface IStETH {
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
    function getSharesByPooledEth(uint256 _pooledEthAmount) external view returns (uint256);
    function submit(address _referral) external payable returns (uint256);
}
