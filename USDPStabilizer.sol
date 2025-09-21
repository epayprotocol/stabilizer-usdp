
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IUSDP {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function totalSupply() external view returns (uint256);
    function manager() external view returns (address);
}

interface IUSDPOracle {
    function latestAnswer() external view returns (uint256);
    function getPrice() external view returns (uint256 price, bool isValid);
    function isValidPrice() external view returns (bool);
}

interface ITreasury {
    function getCollateralValue() external view returns (uint256);
    function hasAvailableCollateral(uint256 amount) external view returns (bool);
    function requestCollateralBacking(uint256 amount) external returns (bool);
}

/// @title USDP Stabilizer - Algorithmic Price Stability Contract
/// @notice Maintains USDP price stability at $1.00 through automated supply adjustments
/// @dev Implements sophisticated algorithms with multiple deviation response levels and security features
contract USDPStabilizer {
    /*//////////////////////////////////////////////////////////////
                                OWNERSHIP
    //////////////////////////////////////////////////////////////*/
    
    address public owner;
    address public pendingOwner;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "UNAUTHORIZED");
        _;
    }
    
    /*//////////////////////////////////////////////////////////////
                            REENTRANCY GUARD
    //////////////////////////////////////////////////////////////*/
    
    uint256 private _status = 1;
    
    modifier nonReentrant() {
        require(_status == 1, "REENTRANCY");
        _status = 2;
        _;
        _status = 1;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 public constant TARGET_PRICE = 1e8; // $1.00 with 8 decimals
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant PRICE_DECIMALS = 8;
    
    // Deviation thresholds (in basis points)
    uint256 public constant SMALL_DEVIATION = 50;    // 0.5%
    uint256 public constant MEDIUM_DEVIATION = 200;  // 2%
    uint256 public constant LARGE_DEVIATION = 500;   // 5%
    uint256 public constant EXTREME_DEVIATION = 1000; // 10%
    
    // Default adjustment rates (in basis points of total supply)
    uint256 public constant SMALL_ADJUSTMENT_RATE = 10;   // 0.1%
    uint256 public constant MEDIUM_ADJUSTMENT_RATE = 50;  // 0.5%
    uint256 public constant LARGE_ADJUSTMENT_RATE = 200;  // 2%
    
    // Time constants
    uint256 public constant MIN_COOLDOWN = 1 hours;
    uint256 public constant MAX_COOLDOWN = 6 hours;
    uint256 public constant DAILY_RESET_PERIOD = 24 hours;
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct StabilizationParameters {
        uint256 smallDeviationThreshold;    // Small deviation threshold (BP)
        uint256 mediumDeviationThreshold;   // Medium deviation threshold (BP)
        uint256 largeDeviationThreshold;    // Large deviation threshold (BP)
        uint256 extremeDeviationThreshold;  // Extreme deviation threshold (BP)
        
        uint256 smallAdjustmentRate;        // Small adjustment rate (BP)
        uint256 mediumAdjustmentRate;       // Medium adjustment rate (BP)
        uint256 largeAdjustmentRate;        // Large adjustment rate (BP)
        
        uint256 minCooldownPeriod;          // Minimum cooldown between adjustments
        uint256 maxCooldownPeriod;          // Maximum cooldown for large adjustments
        uint256 maxDailyAdjustment;         // Maximum daily adjustment (BP of supply)
    }
    
    struct StabilizationState {
        uint256 lastStabilizationTime;     // Last time stabilization was executed
        uint256 lastPriceChecked;          // Last price that was checked
        uint256 currentCooldownPeriod;     // Current cooldown period
        uint256 dailyAdjustmentUsed;       // Adjustment used today (BP)
        uint256 dailyResetTimestamp;       // Daily limit reset timestamp
        bool emergencyHalted;              // Emergency halt flag
    }

    struct PriceDeviationData {
        uint256 currentPrice;
        uint256 targetPrice;
        uint256 deviationBP;
        bool isAboveTarget;
        uint256 adjustmentLevel; // 0=none, 1=small, 2=medium, 3=large, 4=extreme
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/
    
    IUSDP public usdpToken;
    IUSDPOracle public usdpMarketOracle; // Oracle for USDP market price
    IUSDPOracle public usdtOracle;       // Oracle for USDT/USD reference price
    ITreasury public treasury;
    
    StabilizationParameters public params;
    StabilizationState public state;
    
    // Access control
    mapping(address => bool) public authorizedStabilizers;
    mapping(address => bool) public emergencyOperators;
    
    // Statistics tracking
    uint256 public totalMintedForStabilization;
    uint256 public totalBurnedForStabilization;
    uint256 public stabilizationCount;
    uint256 public lastAdjustmentAmount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event StabilizationExecuted(
        uint256 indexed timestamp,
        uint256 priceDeviation,
        uint256 adjustmentAmount,
        bool isMinting,
        uint256 newSupply
    );
    
    event PriceDeviationDetected(
        uint256 indexed timestamp,
        uint256 currentPrice,
        uint256 targetPrice,
        uint256 deviationBP,
        uint256 adjustmentLevel
    );
    
    event EmergencyHalt(uint256 indexed timestamp, uint256 priceDeviation, string reason);
    event EmergencyResume(uint256 indexed timestamp);
    event ParametersUpdated(address indexed updater, uint256 timestamp);
    event CooldownPeriodAdjusted(uint256 oldPeriod, uint256 newPeriod);
    event DailyLimitReset(uint256 timestamp, uint256 newLimit);
    
    event AuthorizedStabilizerChanged(address indexed stabilizer, bool authorized);
    event EmergencyOperatorChanged(address indexed operator, bool authorized);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error StabilizationInCooldown();
    error PriceDataStale();
    error EmergencyHalted();
    error DailyLimitExceeded();
    error InsufficientCollateral();
    error ExtremeDeviationDetected();
    error UnauthorizedStabilizer();
    error InvalidParameters();
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        address _owner,
        address _usdpToken,
        address _usdpMarketOracle,
        address _usdtOracle,
        address _treasury
    ) {
        require(_owner != address(0), "INVALID_OWNER");
        require(_usdpToken != address(0), "INVALID_USDP");
        require(_usdpMarketOracle != address(0), "INVALID_MARKET_ORACLE");
        require(_usdtOracle != address(0), "INVALID_USDT_ORACLE");
        
        owner = _owner;
        usdpToken = IUSDP(_usdpToken);
        usdpMarketOracle = IUSDPOracle(_usdpMarketOracle);
        usdtOracle = IUSDPOracle(_usdtOracle);
        treasury = ITreasury(_treasury);
        
        // Initialize default parameters
        params = StabilizationParameters({
            smallDeviationThreshold: SMALL_DEVIATION,
            mediumDeviationThreshold: MEDIUM_DEVIATION,
            largeDeviationThreshold: LARGE_DEVIATION,
            extremeDeviationThreshold: EXTREME_DEVIATION,
            smallAdjustmentRate: SMALL_ADJUSTMENT_RATE,
            mediumAdjustmentRate: MEDIUM_ADJUSTMENT_RATE,
            largeAdjustmentRate: LARGE_ADJUSTMENT_RATE,
            minCooldownPeriod: MIN_COOLDOWN,
            maxCooldownPeriod: MAX_COOLDOWN,
            maxDailyAdjustment: 200 // 2% daily limit
        });
        
        // Initialize state
        state = StabilizationState({
            lastStabilizationTime: block.timestamp,
            lastPriceChecked: TARGET_PRICE,
            currentCooldownPeriod: MIN_COOLDOWN,
            dailyAdjustmentUsed: 0,
            dailyResetTimestamp: block.timestamp,
            emergencyHalted: false
        });
        
        emit OwnershipTransferred(address(0), _owner);
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyAuthorizedStabilizer() {
        require(authorizedStabilizers[msg.sender] || msg.sender == owner, "UNAUTHORIZED_STABILIZER");
        _;
    }
    
    modifier onlyEmergencyOperator() {
        require(emergencyOperators[msg.sender] || msg.sender == owner, "UNAUTHORIZED_EMERGENCY");
        _;
    }
    
    modifier notEmergencyHalted() {
        require(!state.emergencyHalted, "EMERGENCY_HALTED");
        _;
    }
    
    modifier notInCooldown() {
        require(block.timestamp >= state.lastStabilizationTime + state.currentCooldownPeriod, "IN_COOLDOWN");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        CORE STABILIZATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Main stabilization function to check and adjust USDP supply
    /// @dev Can be called by authorized stabilizers or owner
    function stabilize() external onlyAuthorizedStabilizer notEmergencyHalted notInCooldown nonReentrant {
        // Reset daily limits if needed
        _resetDailyLimitsIfNeeded();
        
        // Get current price deviation
        PriceDeviationData memory deviation = checkPriceDeviation();
        
        // Skip if no significant deviation
        if (deviation.adjustmentLevel == 0) {
            return;
        }
        
        // Calculate optimal adjustment amount
        uint256 adjustmentAmount = calculateAdjustment(deviation);
        
        // Check daily limits
        uint256 adjustmentBP = (adjustmentAmount * BASIS_POINTS) / usdpToken.totalSupply();
        require(state.dailyAdjustmentUsed + adjustmentBP <= params.maxDailyAdjustment, "DAILY_LIMIT_EXCEEDED");
        
        // Execute the adjustment
        if (deviation.isAboveTarget) {
            _executeMint(adjustmentAmount);
        } else {
            _executeBurn(adjustmentAmount);
        }
        
        // Update state
        _updateStateAfterStabilization(deviation, adjustmentAmount, adjustmentBP);
        
        emit StabilizationExecuted(
            block.timestamp,
            deviation.deviationBP,
            adjustmentAmount,
            deviation.isAboveTarget,
            usdpToken.totalSupply()
        );
    }
    
    /// @notice Check current price deviation from target
    /// @return deviation Detailed price deviation data
    function checkPriceDeviation() public returns (PriceDeviationData memory deviation) {
        // Get USDP market price
        (uint256 usdpPrice, bool isValid) = usdpMarketOracle.getPrice();
        require(isValid, "USDP_PRICE_STALE");
        
        // Get USDT reference price (should be ~$1.00)
        uint256 usdtPrice = usdtOracle.latestAnswer();
        
        // Calculate target price adjusted for USDT deviation from $1
        uint256 adjustedTarget = (TARGET_PRICE * usdtPrice) / 1e8;
        
        deviation.currentPrice = usdpPrice;
        deviation.targetPrice = adjustedTarget;
        deviation.isAboveTarget = usdpPrice > adjustedTarget;
        
        // Calculate deviation in basis points
        if (deviation.isAboveTarget) {
            deviation.deviationBP = ((usdpPrice - adjustedTarget) * BASIS_POINTS) / adjustedTarget;
        } else {
            deviation.deviationBP = ((adjustedTarget - usdpPrice) * BASIS_POINTS) / adjustedTarget;
        }
        
        // Determine adjustment level
        deviation.adjustmentLevel = _determineAdjustmentLevel(deviation.deviationBP);
        
        // Check for extreme deviation
        require(deviation.deviationBP <= params.extremeDeviationThreshold, "EXTREME_DEVIATION");
        
        if (deviation.adjustmentLevel > 0) {
            emit PriceDeviationDetected(
                block.timestamp,
                deviation.currentPrice,
                deviation.targetPrice,
                deviation.deviationBP,
                deviation.adjustmentLevel
            );
        }
        
        return deviation;
    }
    
    /// @notice Calculate optimal adjustment amount based on price deviation
    /// @param deviation Price deviation data
    /// @return adjustmentAmount Amount to mint or burn
    function calculateAdjustment(PriceDeviationData memory deviation) public view returns (uint256) {
        if (deviation.adjustmentLevel == 0) return 0;
        
        uint256 totalSupply = usdpToken.totalSupply();
        uint256 baseAdjustmentRate;
        
        // Determine base adjustment rate based on deviation level
        if (deviation.adjustmentLevel == 1) {
            baseAdjustmentRate = params.smallAdjustmentRate;
        } else if (deviation.adjustmentLevel == 2) {
            baseAdjustmentRate = params.mediumAdjustmentRate;
        } else if (deviation.adjustmentLevel == 3) {
            baseAdjustmentRate = params.largeAdjustmentRate;
        } else {
            // Extreme case - use large rate but will be caught by extreme check
            baseAdjustmentRate = params.largeAdjustmentRate;
        }
        
        // Calculate base adjustment amount
        uint256 baseAmount = (totalSupply * baseAdjustmentRate) / BASIS_POINTS;
        
        // Apply dynamic scaling based on deviation magnitude
        uint256 scalingFactor = _calculateScalingFactor(deviation);
        uint256 adjustmentAmount = (baseAmount * scalingFactor) / BASIS_POINTS;
        
        // Apply remaining daily limit constraint
        uint256 remainingDailyBP = params.maxDailyAdjustment - state.dailyAdjustmentUsed;
        uint256 maxAllowedAmount = (totalSupply * remainingDailyBP) / BASIS_POINTS;
        
        return adjustmentAmount > maxAllowedAmount ? maxAllowedAmount : adjustmentAmount;
    }
    
    /// @notice Execute mint operation for stabilization
    /// @param amount Amount to mint
    function executeMint(uint256 amount) external onlyOwner nonReentrant {
        require(!state.emergencyHalted, "EMERGENCY_HALTED");
        require(amount > 0, "INVALID_AMOUNT");
        _executeMint(amount);
    }
    
    /// @notice Execute burn operation for stabilization
    /// @param amount Amount to burn
    function executeBurn(uint256 amount) external onlyOwner nonReentrant {
        require(!state.emergencyHalted, "EMERGENCY_HALTED");
        require(amount > 0, "INVALID_AMOUNT");
        _executeBurn(amount);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL STABILIZATION LOGIC
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Execute minting when USDP price is above target
    /// @param amount Amount to mint
    function _executeMint(uint256 amount) internal {
        // Verify collateral backing is available
        if (address(treasury) != address(0)) {
            require(treasury.hasAvailableCollateral(amount), "INSUFFICIENT_COLLATERAL");
            require(treasury.requestCollateralBacking(amount), "COLLATERAL_REQUEST_FAILED");
        }
        
        // Mint tokens to treasury or designated recipient
        address mintRecipient = address(treasury) != address(0) ? address(treasury) : address(this);
        usdpToken.mint(mintRecipient, amount);
        
        totalMintedForStabilization += amount;
        lastAdjustmentAmount = amount;
    }
    
    /// @notice Execute burning when USDP price is below target
    /// @param amount Amount to burn
    function _executeBurn(uint256 amount) internal {
        // For burning, we need to have tokens available
        // This assumes the stabilizer contract holds USDP tokens or can access them
        address burnSource = address(this);
        
        // Alternative: burn from treasury if it has tokens
        if (address(treasury) != address(0)) {
            // Could implement treasury.transferForBurn(amount) here
            burnSource = address(treasury);
        }
        
        usdpToken.burn(burnSource, amount);
        
        totalBurnedForStabilization += amount;
        lastAdjustmentAmount = amount;
    }
    
    /// @notice Determine adjustment level based on deviation magnitude
    /// @param deviationBP Deviation in basis points
    /// @return level Adjustment level (0-4)
    function _determineAdjustmentLevel(uint256 deviationBP) internal view returns (uint256 level) {
        if (deviationBP >= params.extremeDeviationThreshold) {
            return 4; // Extreme
        } else if (deviationBP >= params.largeDeviationThreshold) {
            return 3; // Large
        } else if (deviationBP >= params.mediumDeviationThreshold) {
            return 2; // Medium
        } else if (deviationBP >= params.smallDeviationThreshold) {
            return 1; // Small
        } else {
            return 0; // No action needed
        }
    }
    
    /// @notice Calculate dynamic scaling factor for adjustment amount
    /// @param deviation Price deviation data
    /// @return scalingFactor Scaling factor in basis points
    function _calculateScalingFactor(PriceDeviationData memory deviation) internal view returns (uint256) {
        // Base scaling is 100% (BASIS_POINTS)
        uint256 scalingFactor = BASIS_POINTS;
        
        // Apply aggressive scaling for larger deviations
        if (deviation.adjustmentLevel == 3) { // Large deviation
            // Scale between 100% to 200% based on how close to extreme threshold
            uint256 progressToExtreme = (deviation.deviationBP - params.largeDeviationThreshold) * BASIS_POINTS
                / (params.extremeDeviationThreshold - params.largeDeviationThreshold);
            scalingFactor = BASIS_POINTS + progressToExtreme;
        } else if (deviation.adjustmentLevel == 2) { // Medium deviation
            // Scale between 80% to 120%
            uint256 progressToLarge = (deviation.deviationBP - params.mediumDeviationThreshold) * BASIS_POINTS
                / (params.largeDeviationThreshold - params.mediumDeviationThreshold);
            scalingFactor = (8000 + (progressToLarge * 40) / 100);
        }
        
        return scalingFactor;
    }
    
    /// @notice Update state after successful stabilization
    /// @param deviation Price deviation data
    /// @param adjustmentAmount Amount that was adjusted
    /// @param adjustmentBP Adjustment in basis points
    function _updateStateAfterStabilization(
        PriceDeviationData memory deviation,
        uint256 adjustmentAmount,
        uint256 adjustmentBP
    ) internal {
        state.lastStabilizationTime = block.timestamp;
        state.lastPriceChecked = deviation.currentPrice;
        state.dailyAdjustmentUsed += adjustmentBP;
        stabilizationCount++;
        
        // Adjust cooldown period based on adjustment magnitude
        if (deviation.adjustmentLevel >= 3) {
            state.currentCooldownPeriod = params.maxCooldownPeriod;
        } else if (deviation.adjustmentLevel == 2) {
            state.currentCooldownPeriod = (params.minCooldownPeriod + params.maxCooldownPeriod) / 2;
        } else {
            state.currentCooldownPeriod = params.minCooldownPeriod;
        }
        
        emit CooldownPeriodAdjusted(state.currentCooldownPeriod, state.currentCooldownPeriod);
    }
    
    /// @notice Reset daily limits if 24 hours have passed
    function _resetDailyLimitsIfNeeded() internal {
        if (block.timestamp >= state.dailyResetTimestamp + DAILY_RESET_PERIOD) {
            state.dailyAdjustmentUsed = 0;
            state.dailyResetTimestamp = block.timestamp;
            emit DailyLimitReset(block.timestamp, params.maxDailyAdjustment);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ADMINISTRATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Update stabilization parameters
    /// @param newParams New parameter values
    function updateParameters(StabilizationParameters calldata newParams) external onlyOwner {
        // Validate parameters
        require(newParams.smallDeviationThreshold < newParams.mediumDeviationThreshold, "INVALID_THRESHOLDS");
        require(newParams.mediumDeviationThreshold < newParams.largeDeviationThreshold, "INVALID_THRESHOLDS");
        require(newParams.largeDeviationThreshold < newParams.extremeDeviationThreshold, "INVALID_THRESHOLDS");
        require(newParams.minCooldownPeriod <= newParams.maxCooldownPeriod, "INVALID_COOLDOWN");
        require(newParams.maxDailyAdjustment <= 1000, "DAILY_LIMIT_TOO_HIGH"); // Max 10%
        
        params = newParams;
        emit ParametersUpdated(msg.sender, block.timestamp);
    }
    
    /// @notice Set authorized stabilizer
    /// @param stabilizer Address to authorize/deauthorize
    /// @param authorized True to authorize, false to revoke
    function setAuthorizedStabilizer(address stabilizer, bool authorized) external onlyOwner {
        authorizedStabilizers[stabilizer] = authorized;
        emit AuthorizedStabilizerChanged(stabilizer, authorized);
    }
    
    /// @notice Set emergency operator
    /// @param operator Address to authorize/deauthorize
    /// @param authorized True to authorize, false to revoke
    function setEmergencyOperator(address operator, bool authorized) external onlyOwner {
        emergencyOperators[operator] = authorized;
        emit EmergencyOperatorChanged(operator, authorized);
    }
    
    /// @notice Emergency halt stabilization
    /// @param reason Reason for halt
    function emergencyHalt(string calldata reason) external onlyEmergencyOperator {
        state.emergencyHalted = true;
        emit EmergencyHalt(block.timestamp, 0, reason);
    }
    
    /// @notice Resume stabilization after emergency halt
    function emergencyResume() external onlyOwner {
        state.emergencyHalted = false;
        emit EmergencyResume(block.timestamp);
    }
    
    /// @notice Update oracle addresses
    /// @param _usdpMarketOracle New USDP market oracle
    /// @param _usdtOracle New USDT oracle
    function updateOracles(address _usdpMarketOracle, address _usdtOracle) external onlyOwner {
        if (_usdpMarketOracle != address(0)) {
            usdpMarketOracle = IUSDPOracle(_usdpMarketOracle);
        }
        if (_usdtOracle != address(0)) {
            usdtOracle = IUSDPOracle(_usdtOracle);
        }
    }
    
    /// @notice Update treasury address
    /// @param _treasury New treasury address
    function updateTreasury(address _treasury) external onlyOwner {
        treasury = ITreasury(_treasury);
    }
    
    /// @notice Transfer ownership to new owner
    /// @param newOwner New owner address
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "INVALID_ADDRESS");
        pendingOwner = newOwner;
    }
    
    /// @notice Accept ownership transfer
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "NOT_PENDING_OWNER");
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, owner);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Get current stabilization status
    /// @return isActive Whether stabilization is active
    /// @return nextStabilizationTime When next stabilization can occur
    /// @return currentDeviation Current price deviation
    /// @return dailyLimitRemaining Remaining daily adjustment limit
    function getStabilizationStatus() external view returns (
        bool isActive,
        uint256 nextStabilizationTime,
        uint256 currentDeviation,
        uint256 dailyLimitRemaining
    ) {
        isActive = !state.emergencyHalted;
        nextStabilizationTime = state.lastStabilizationTime + state.currentCooldownPeriod;
        
        // For view function, we calculate deviation without emitting events
        try usdpMarketOracle.getPrice() returns (uint256 usdpPrice, bool isValid) {
            if (isValid) {
                uint256 usdtPrice = usdtOracle.latestAnswer();
                uint256 adjustedTarget = (TARGET_PRICE * usdtPrice) / 1e8;
                if (usdpPrice > adjustedTarget) {
                    currentDeviation = ((usdpPrice - adjustedTarget) * BASIS_POINTS) / adjustedTarget;
                } else {
                    currentDeviation = ((adjustedTarget - usdpPrice) * BASIS_POINTS) / adjustedTarget;
                }
            }
        } catch {
            currentDeviation = 0;
        }
        
        dailyLimitRemaining = params.maxDailyAdjustment > state.dailyAdjustmentUsed ?
            params.maxDailyAdjustment - state.dailyAdjustmentUsed : 0;
    }
    
    /// @notice Get stabilization statistics
    /// @return totalMinted Total minted for stabilization
    /// @return totalBurned Total burned for stabilization
    /// @return stabilizations Total number of stabilizations
    /// @return lastAdjustment Last adjustment amount
    function getStatistics() external view returns (
        uint256 totalMinted,
        uint256 totalBurned,
        uint256 stabilizations,
        uint256 lastAdjustment
    ) {
        return (
            totalMintedForStabilization,
            totalBurnedForStabilization,
            stabilizationCount,
            lastAdjustmentAmount
        );
    }
    
    /// @notice Get current parameters
    /// @return Current stabilization parameters
    function getParameters() external view returns (StabilizationParameters memory) {
        return params;
    }
    
    /// @notice Get current state
    /// @return Current stabilization state
    function getState() external view returns (StabilizationState memory) {
        return state;
    }
}