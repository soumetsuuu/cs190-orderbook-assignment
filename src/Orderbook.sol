// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOrderbook} from "./IOrderbook.sol";

/// @dev Minimal ERC20 surface the orderbook needs. The provided `MockERC20`
///      implements all of these methods (plus `mint`).
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

/// @title Orderbook (template)
/// @notice Skeleton to complete. The constructor, immutable
///         token wiring, and the two trivial getters are already done —
///         everything else reverts with `"NotImplemented"`.
///
///         You are free to add additional state, structs, errors, and
///         helper functions. The only hard constraints are:
///         (1) keep the `IOrderbook` ABI exactly as declared in the
///             interface (the grading harness depends on it), and
///         (2) keep `baseToken`/`quoteToken` as immutables set in the
///             constructor.
contract Orderbook is IOrderbook {
    IERC20 public immutable baseToken;
    IERC20 public immutable quoteToken;

    /// @dev Suggested events. These are a starting point — your
    ///      implementation may emit a different set, rename them, or omit
    ///      events entirely. Nothing in the grading harness depends on
    ///      these signatures.
    event OrderPlaced(
        uint256 indexed orderId,
        address indexed maker,
        Side side,
        uint256 price,
        uint256 amount
    );
    event OrderFilled(
        uint256 indexed orderId,
        address indexed taker,
        uint256 fillAmount,
        uint256 fillPrice
    );
    event OrderCleared();

    //new
    struct Order {
        address maker;
        Side side;
        uint256 price;
        uint256 amount;
    }

    //new
    mapping(uint256 => Order) private orders;
    uint256[] private bids;
    uint256[] private asks;
    uint256 private nextOrderId = 1;

    constructor(address _baseToken, address _quoteToken) {
        require(_baseToken != address(0), "baseToken=0");
        require(_quoteToken != address(0), "quoteToken=0");
        require(_baseToken != _quoteToken, "base==quote");
        baseToken = IERC20(_baseToken);
        quoteToken = IERC20(_quoteToken);
    }

    function getBaseToken() external view returns (address) {
        return address(baseToken);
    }

    function getQuoteToken() external view returns (address) {
        return address(quoteToken);
    }

    function placeLimitOrder(Side side, uint256 price, uint256 amount) external returns (uint256) {
        require(price > 0, "price is 0");
        require(amount > 0, "amount is 0");

        if (side == Side.BUY) {
            uint256 quoteRequired = (amount * price) / 1e18;
            require(quoteToken.transferFrom(msg.sender, address(this), quoteRequired), "quote collateral transfer failed for buy order");
        } else {
            require(baseToken.transferFrom(msg.sender, address(this), amount), "base collateral transfer failed for sell order");
        }

        uint256 orderId = nextOrderId++;
        orders[orderId] = Order({
            maker: msg.sender,
            side: side,
            price: price,
            amount: amount
        });

        if (side == Side.BUY) {
            insertBid(orderId);
        } else {
            insertAsk(orderId);
        }

        emit OrderPlaced(orderId, msg.sender, side, price, amount);
        return orderId;
    }

    function placeMarketOrder(Side side, uint256 amount) external {
        require(amount > 0, "amount is 0");
        if (side == Side.BUY) {
            executeMarketBuy(amount);
        } else {
            executeMarketSell(amount);
        }
    }

    function executeMarketBuy(uint256 amount) private {
        uint256 remaining = amount;

        while (remaining > 0 && asks.length > 0) {
            uint256 orderId = asks[0];
            Order storage order = orders[orderId];
            if (order.amount == 0) { //this check is maybe not needed
                removeAskAt(0);
                delete orders[orderId];
                continue;
            }

            uint256 fillAmount = order.amount <= remaining ? order.amount : remaining;
            uint256 quoteAmount = (fillAmount * order.price) / 1e18;

            order.amount -= fillAmount;
            remaining -= fillAmount;

            emit OrderFilled(orderId, msg.sender, fillAmount, order.price);

            require(quoteToken.transferFrom(msg.sender, order.maker, quoteAmount), "quote transfer failed");
            require(baseToken.transfer(msg.sender, fillAmount), "base transfer failed");

            if (order.amount == 0) {
                removeAskAt(0);
                delete orders[orderId];
            }
        }

    }
    function executeMarketSell(uint256 amount) private {
        uint256 remaining = amount;

        while (remaining > 0 && bids.length > 0) {
            uint256 orderId = bids[0];
            Order storage order = orders[orderId];
            if (order.amount == 0) { //again this check may not be needed
                removeBidAt(0);
                delete orders[orderId];
                continue;
            }

            uint256 fillAmount = order.amount <= remaining ? order.amount : remaining;
            uint256 quoteAmount = (fillAmount * order.price) / 1e18;

            order.amount -= fillAmount;
            remaining -= fillAmount;

            emit OrderFilled(orderId, msg.sender, fillAmount, order.price);

            require(baseToken.transferFrom(msg.sender, order.maker, fillAmount), "base transfer failed");
            require(quoteToken.transfer(msg.sender, quoteAmount), "quote transfer failed");

            if (order.amount == 0) {
                removeBidAt(0);
                delete orders[orderId];
            }
        }
    }

    function removeBidAt(uint256 index) private {
        uint256 last = bids.length - 1;
        for (uint256 i = index; i < last; i++) {
            bids[i] = bids[i + 1];
        }
        bids.pop();
    }

    function removeAskAt(uint256 index) private {
        uint256 last = asks.length - 1;
        for (uint256 i = index; i < last; i++) {
            asks[i] = asks[i + 1];
        }
        asks.pop();
    }

    function insertBid(uint256 orderId) private {
        uint256 price = orders[orderId].price;
        uint256 origLength = bids.length;

        bids.push(orderId);

        uint256 i = origLength;
        while (i > 0 && orders[bids[i - 1]].price < price) {
            bids[i] = bids[i - 1];
            i--;
        }
        bids[i] = orderId;
    }

    function insertAsk(uint256 orderId) private {
        uint256 price = orders[orderId].price;
        uint256 origLength = asks.length;

        asks.push(orderId);

        uint256 i = origLength;
        while (i > 0 && orders[asks[i - 1]].price > price) {
            asks[i] = asks[i - 1];
            i--;
        }
        asks[i] = orderId;
    }

    function clear() external {
        uint256 bidsLength = bids.length;
        for (uint256 i = 0; i < bidsLength; i++) {
            uint256 orderId = bids[i];
            Order storage order = orders[orderId];
            if (order.amount > 0) {
                uint256 refundQuote = (order.amount * order.price) / 1e18;
                require(quoteToken.transfer(order.maker, refundQuote), "refund quote failed");
            }
            delete orders[orderId];
        }

        uint256 asksLength = asks.length;
        for (uint256 i = 0; i < asksLength; i++) {
            uint256 orderId = asks[i];
            Order storage order = orders[orderId];
            if (order.amount > 0) {
                require(baseToken.transfer(order.maker, order.amount), "refund base failed");
            }
            delete orders[orderId];
        }

        delete bids;
        delete asks;

        emit OrderCleared();
    }

    function getBidsCount() external view returns (uint256) {
        return bids.length;
    }

    function getAsksCount() external view returns (uint256) {
        return asks.length;
    }

    function getMidPrice() external view returns (uint256) {
        require(bids.length > 0 && asks.length > 0, "at least one in each");
        uint256 bestBid = orders[bids[0]].price;
        uint256 bestAsk = orders[asks[0]].price;
        return (bestBid + bestAsk) / 2;
    }
}
