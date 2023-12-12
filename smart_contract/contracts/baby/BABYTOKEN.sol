// SPDX-License-Identifier: MIT LICENSE

pragma solidity =0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "contracts/libs/SafeERC20NoRevert.sol";
import "contracts/interfaces/IUniswapV2Factory.sol";
import "contracts/interfaces/IUniswapV2Router02.sol";
import "contracts/baby/BABYTOKENDividendTracker.sol";
import "contracts/BaseToken.sol";

contract BABYTOKEN is ERC20, Ownable, BaseToken {
    using SafeMath for uint256;
    using Address for address;
    using Address for address payable;
    using SafeERC20 for IERC20;

    uint256 public constant VERSION = 4;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    bool private swapping;

    BABYTOKENDividendTracker public dividendTracker;

    address public rewardToken;

    uint256 public swapTokensAtAmount;

    uint256 public tokenRewardsFee;
    uint256 public liquidityFee;
    uint256 public marketingFee;
    uint256 public totalFees;

    address public _marketingWalletAddress;

    uint256 public gasForProcessing;

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;

    event ExcludeFromFees(address indexed account);
    event ExcludeMultipleAccountsFromFees(address[] accounts);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event GasForProcessingUpdated(
        uint256 indexed newValue,
        uint256 indexed oldValue
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(uint256 tokensSwapped, uint256 amount);

    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address[4] memory addrs, // reward, router, marketing wallet, dividendTracker
        uint256[3] memory feeSettings, // rewards, liquidity, marketing
        uint256 minimumTokenBalanceForDividends_,
        address serviceFeeReceiver_,
        uint256 serviceFee_
    ) payable ERC20(name_, symbol_) {
        rewardToken = addrs[0];
        _marketingWalletAddress = addrs[2];
        require(
            msg.sender != _marketingWalletAddress,
            "Owner and marketing wallet cannot be the same"
        );
        require(
            !_marketingWalletAddress.isContract(),
            "Marketing wallet cannot be a contract"
        );

        tokenRewardsFee = feeSettings[0];
        liquidityFee = feeSettings[1];
        marketingFee = feeSettings[2];
        totalFees = tokenRewardsFee.add(liquidityFee).add(marketingFee);
        require(totalFees <= 25, "Total fee is over 25%");
        swapTokensAtAmount = totalSupply_.div(1000); // 0.1%

        // use by default 300,000 gas to process auto-claiming dividends
        gasForProcessing = 300000;

        dividendTracker = BABYTOKENDividendTracker(
            payable(Clones.clone(addrs[3]))
        );
        dividendTracker.initialize(
            rewardToken,
            minimumTokenBalanceForDividends_
        );

/*        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(addrs[1]);
        // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;
        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);*/

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(address(0xdead));
        //dividendTracker.excludeFromDividends(address(_uniswapV2Router));
        // exclude from paying fees or having max transaction amount
        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[_marketingWalletAddress] = true;
        _isExcludedFromFees[address(this)] = true;

        /* _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again */

        _mint(owner(), totalSupply_);

        emit TokenCreated(owner(), address(this), TokenType.baby, VERSION);

        payable(serviceFeeReceiver_).transfer(serviceFee_);
    }

    receive() external payable {}

    function setSwapTokensAtAmount(uint256 amount) external onlyOwner {
        require(
            amount > totalSupply() / 10**5,
            "BABYTOKEN: Amount must be greater than 0.001% of total supply"
        );
        swapTokensAtAmount = amount;
    }

    function excludeFromFees(address account) external onlyOwner {
        require(
            !_isExcludedFromFees[account],
            "BABYTOKEN: Account is already excluded"
        );
        _isExcludedFromFees[account] = true;

        emit ExcludeFromFees(account);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts)
    external
    onlyOwner
    {
        for (uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = true;
        }

        emit ExcludeMultipleAccountsFromFees(accounts);
    }

    function setMarketingWallet(address payable wallet) external onlyOwner {
        require(
            wallet != address(0),
            "BABYTOKEN: The marketing wallet cannot be the value of zero"
        );
        require(!wallet.isContract(), "Marketing wallet cannot be a contract");
        _marketingWalletAddress = wallet;
    }

    function setTokenRewardsFee(uint256 value) external onlyOwner {
        tokenRewardsFee = value;
        totalFees = tokenRewardsFee.add(liquidityFee).add(marketingFee);
        require(totalFees <= 25, "Total fee is over 25%");
    }

    function setLiquiditFee(uint256 value) external onlyOwner {
        liquidityFee = value;
        totalFees = tokenRewardsFee.add(liquidityFee).add(marketingFee);
        require(totalFees <= 25, "Total fee is over 25%");
    }

    function setMarketingFee(uint256 value) external onlyOwner {
        marketingFee = value;
        totalFees = tokenRewardsFee.add(liquidityFee).add(marketingFee);
        require(totalFees <= 25, "Total fee is over 25%");
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "BABYTOKEN: Automated market maker pair is already set to that value"
        );
        automatedMarketMakerPairs[pair] = value;

        if (value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(
            newValue >= 200000 && newValue <= 500000,
            "BABYTOKEN: gasForProcessing must be between 200,000 and 500,000"
        );
        require(
            newValue != gasForProcessing,
            "BABYTOKEN: Cannot update gasForProcessing to same value"
        );
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns (uint256) {
        return dividendTracker.claimWait();
    }

    function updateMinimumTokenBalanceForDividends(uint256 amount)
    external
    onlyOwner
    {
        dividendTracker.updateMinimumTokenBalanceForDividends(amount);
    }

    function getMinimumTokenBalanceForDividends()
    external
    view
    returns (uint256)
    {
        return dividendTracker.minimumTokenBalanceForDividends();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account)
    public
    view
    returns (uint256)
    {
        dividendTracker.withdrawableDividendOf(account);
        return 1;
    }

    function dividendTokenBalanceOf(address account)
    public
    view
    returns (uint256)
    {
        return dividendTracker.balanceOf(account);
    }

    function excludeFromDividends(address account) external onlyOwner {
        dividendTracker.excludeFromDividends(account);
    }

    function isExcludedFromDividends(address account)
    public
    view
    returns (bool)
    {
        return dividendTracker.isExcludedFromDividends(account);
    }

    function getAccountDividendsInfo(address account)
    external
    view
    returns (
        address,
        int256,
        int256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    )
    {
        return dividendTracker.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
    external
    view
    returns (
        address,
        int256,
        int256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    )
    {
        return dividendTracker.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external {
        dividendTracker.process(gas);
    }

    function claim() external {
        dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view returns (uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns (uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != owner() &&
            to != owner() &&
            totalFees > 0
        ) {
            swapping = true;

            if (marketingFee > 0) {
                uint256 marketingTokens = contractTokenBalance
                    .mul(marketingFee)
                    .div(totalFees);
                swapAndSendToFee(marketingTokens);
            }

            if (liquidityFee > 0) {
                uint256 swapTokens = contractTokenBalance.mul(liquidityFee).div(
                    totalFees
                );
                swapAndLiquify(swapTokens);
            }

            uint256 sellTokens = balanceOf(address(this));
            if (sellTokens > 0) {
                swapAndSendDividends(sellTokens);
            }

            swapping = false;
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if (takeFee && totalFees > 0) {
            uint256 fees = amount.mul(totalFees).div(100);
            amount = amount.sub(fees);

            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);

        try
        dividendTracker.setBalance(payable(from), balanceOf(from))
        {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}
        if (!swapping) {
            uint256 gas = gasForProcessing;
            try dividendTracker.process(gas) {
            } catch {}
        }
    }

    function swapAndSendToFee(uint256 tokens) private {
        uint256 initialCAKEBalance = IERC20(rewardToken).balanceOf(
            address(this)
        );

        swapTokensForCake(tokens);
        uint256 newBalance = (IERC20(rewardToken).balanceOf(address(this))).sub(
            initialCAKEBalance
        );
        IERC20(rewardToken).safeTransfer(_marketingWalletAddress, newBalance);
    }

    function swapAndLiquify(uint256 tokens) private {
        // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapTokensForCake(uint256 tokenAmount) private {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = rewardToken;

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{ value: ethAmount }(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0xdead),
            block.timestamp
        );
    }

    function swapAndSendDividends(uint256 tokens) private {
        swapTokensForCake(tokens);
        uint256 dividends = IERC20(rewardToken).balanceOf(address(this));
        bool success = SafeERC20NoRevert.safeTransfer(
            IERC20(rewardToken),
            address(dividendTracker),
            dividends
        );
        if (success) {
            dividendTracker.distributeCAKEDividends(dividends);
            emit SendDividends(tokens, dividends);
        }
    }
}