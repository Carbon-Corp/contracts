//SPDX-License-Identifier: MIT

/**
    This is a DEX
    CC Token Holders can earn from their minted tokens here
    LP's can contribute to liquidity and get CCLT ERC20 token  
 */

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./CC_CertificateToken.sol";


contract CCMarketPlace is Ownable, ERC20 {
    IERC20 public immutable asset;
    IERC20 public immutable otherToken;
    CC_CertificateToken public Certificate;

    uint public assetReserve;
    uint public otherTokenReserve;

    constructor(
        
        IERC20 asset_,
        IERC20 otherToken_

    ) Ownable(msg.sender) ERC20("Carbon Corps Liquidity Token", "CCLT") {
        asset = asset_;
        otherToken = otherToken_;
        Certificate = new CC_CertificateToken();
    }

    function swapCC(
       
        uint _amountIn
    ) external returns (uint amountOut) {
        
        require(_amountIn > 0, "amountIn = 0");

        asset.transferFrom(msg.sender, address(this), _amountIn);

        /**
        
        SWAP RATE CALCULATION USING CONSTANT PRODUCT   
        xy = k
        (x + dx)(y - dy) = k
        y - dy = k / (x + dx)
        y - k / (x + dx) = dy
        y - xy / (x + dx) = dy
        (yx + ydx - xy) / (x + dx) = dy
        ydx / (x + dx) = dy

        with a 10% fee: can be made adjustible later
         */

        //safe math?
        uint amountInWithFee = (_amountIn * 900) / 1000;

        amountOut =
            (otherTokenReserve * amountInWithFee) /
            (assetReserve + amountInWithFee);

        otherToken.transfer(msg.sender, amountOut);

        _updateReserves(
            asset.balanceOf(address(this)),
            otherToken.balanceOf(address(this))
        );
    }

    //TODO: add functionality to issue certificate, and burn received tokens
    function swapOtherToken(
        uint _amountIn
    ) external returns (uint amountOut) {
        
        require(_amountIn > 0, "amountIn = 0");

        otherToken.transferFrom(msg.sender, address(this), _amountIn);

        /**
        
        SWAP RATE CALCULATION USING CONSTANT PRODUCT   
        xy = k
        (x + dx)(y - dy) = k
        y - dy = k / (x + dx)
        y - k / (x + dx) = dy
        y - xy / (x + dx) = dy
        (yx + ydx - xy) / (x + dx) = dy
        ydx / (x + dx) = dy

        with a 10% fee: can be made adjustible later
         */

        //safe math?
        uint amountInWithFee = (_amountIn * 900) / 1000;

        amountOut =
            (assetReserve * amountInWithFee) /
            (otherTokenReserve + amountInWithFee);

        //burn mechanism: transfer to buyer, then burn?
        asset.transfer(msg.sender, amountOut);

        //burn CC token
        asset.transferFrom(msg.sender,address(0), amountOut);

        //mint certificate
        Certificate.mint(msg.sender, amountOut);

        _updateReserves(
            asset.balanceOf(address(this)),
            otherToken.balanceOf(address(this))
        );
    }

    function addLiquidity(
        uint _assetAmount,
        uint _otherTokenAmount
    ) external returns (uint shares) {
        asset.transferFrom(msg.sender, address(this), _assetAmount);
        otherToken.transferFrom(msg.sender, address(this), _otherTokenAmount);

        /*
        How much dx, dy to add?

        xy = k
        (x + dx)(y + dy) = k'

        No price change, before and after adding liquidity
        x / y = (x + dx) / (y + dy)

        x(y + dy) = y(x + dx)
        x * dy = y * dx

        x / y = dx / dy
        dy = y / x * dx
        */

        if (assetReserve > 0 || otherTokenReserve > 0) {
            require(
                assetReserve * _otherTokenAmount ==
                    otherTokenReserve * _assetAmount,
                " x/y != dx/dy"
            );
        }

        /*
        How many shares to mint?

        f(x, y) = value of liquidity
        We will define f(x, y) = sqrt(xy)

        L0 = f(x, y)
        L1 = f(x + dx, y + dy)
        T = total shares
        s = shares to mint

        Total shares should increase proportional to increase in liquidity
        L1 / L0 = (T + s) / T

        L1 * T = L0 * (T + s)

        (L1 - L0) * T / L0 = s 
        */

        /*
        Claim
        (L1 - L0) / L0 = dx / x = dy / y

        Proof
        --- Equation 1 ---
        (L1 - L0) / L0 = (sqrt((x + dx)(y + dy)) - sqrt(xy)) / sqrt(xy)
        
        dx / dy = x / y so replace dy = dx * y / x

        --- Equation 2 ---
        Equation 1 = (sqrt(xy + 2ydx + dx^2 * y / x) - sqrt(xy)) / sqrt(xy)

        Multiply by sqrt(x) / sqrt(x)
        Equation 2 = (sqrt(x^2y + 2xydx + dx^2 * y) - sqrt(x^2y)) / sqrt(x^2y)
                   = (sqrt(y)(sqrt(x^2 + 2xdx + dx^2) - sqrt(x^2)) / (sqrt(y)sqrt(x^2))
        
        sqrt(y) on top and bottom cancels out

        --- Equation 3 ---
        Equation 2 = (sqrt(x^2 + 2xdx + dx^2) - sqrt(x^2)) / (sqrt(x^2)
        = (sqrt((x + dx)^2) - sqrt(x^2)) / sqrt(x^2)  
        = ((x + dx) - x) / x
        = dx / x

        Since dx / dy = x / y,
        dx / x = dy / y

        Finally
        (L1 - L0) / L0 = dx / x = dy / y
        */

        if (totalSupply() == 0) {
            shares = _sqrt(_assetAmount * _otherTokenAmount);
        } else {
            shares = _min(
                (_assetAmount * totalSupply()) / assetReserve,
                (_otherTokenAmount * totalSupply()) / otherTokenReserve
            );
        }
        require(shares > 0, "shares = 0");
        _mint(msg.sender, shares);

        _updateReserves(
            asset.balanceOf(address(this)),
            otherToken.balanceOf(address(this))
        );
    }

    //TODO: add a dynamic interest calculator so that LP gain on their investment; or just change to ERC4626
    function removeLiquidity(
        uint _shares
    ) external returns (uint _assetAmount, uint _otherTokenAmount) {
        /*
        Claim
        dx, dy = amount of liquidity to remove
        dx = s / T * x
        dy = s / T * y

        Proof
        Let's find dx, dy such that
        v / L = s / T
        
        where
        v = f(dx, dy) = sqrt(dxdy)
        L = total liquidity = sqrt(xy)
        s = shares
        T = total supply

        --- Equation 1 ---
        v = s / T * L
        sqrt(dxdy) = s / T * sqrt(xy)

        Amount of liquidity to remove must not change price so 
        dx / dy = x / y

        replace dy = dx * y / x
        sqrt(dxdy) = sqrt(dx * dx * y / x) = dx * sqrt(y / x)

        Divide both sides of Equation 1 with sqrt(y / x)
        dx = s / T * sqrt(xy) / sqrt(y / x)
           = s / T * sqrt(x^2) = s / T * x

        Likewise
        dy = s / T * y
        */

        require(_shares > 0, "Cannot redeem 0 shares");

        uint assetBalance = asset.balanceOf(address(this));
        uint otherTokenBalance = otherToken.balanceOf(address(this));

        //asset amount out
        _assetAmount = (_shares * assetBalance) / totalSupply();
        //other token amount out
        _otherTokenAmount = (_shares * otherTokenBalance) / totalSupply();
        require(
            _assetAmount > 0 && _otherTokenAmount > 0,
            "Cannot redeem for zero underlying assets & otherTokens"
        );

        _burn(msg.sender, _shares);
        _updateReserves(
            assetBalance - _assetAmount,
            otherTokenBalance - _otherTokenAmount
        );

        asset.transfer(msg.sender, _assetAmount);
        otherToken.transfer(msg.sender, _otherTokenAmount);
    }

    function _updateReserves(
        uint _assetReserve,
        uint _otherTokenReserve
    ) private {
        assetReserve = _assetReserve;
        otherTokenReserve = _otherTokenReserve;
    }

    function _sqrt(uint y) private pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }
}
