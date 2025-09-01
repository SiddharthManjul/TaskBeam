pragma circom 2.0.0;

// Utility template for range checking (0 <= value <= max_value)
template RangeCheck(max_bits) {
    signal input value;
    signal input max_value;
    signal output valid;
    
    // Check if value <= max_value using bit decomposition
    component lt = LessThanEq(max_bits);
    lt.in[0] <== value;
    lt.in[1] <== max_value;
    valid <== lt.out;
}

// Template for safe division with scaling factor
template SafeDivision(scale_bits) {
    signal input numerator;
    signal input denominator;
    signal output quotient;
    signal output remainder;
    
    // Constraint: numerator = quotient * denominator + remainder
    // With scaling: scaled_quotient = (numerator * 2^scale_bits) / denominator
    
    signal scaled_numerator <== numerator * (2 ** scale_bits);
    
    // Ensure denominator is not zero
    component non_zero = IsZero();
    non_zero.in <== denominator;
    non_zero.out === 0; // Force denominator to be non-zero
    
    // Division constraint
    scaled_numerator === quotient * denominator + remainder;
    
    // Remainder must be less than denominator
    component range_check = LessThan(32);
    range_check.in[0] <== remainder;
    range_check.in[1] <== denominator;
    range_check.out === 1;
}

// Template for weighted sum calculation
template WeightedSum(n) {
    signal input values[n];
    signal input weights[n];
    signal output sum;
    
    component multipliers[n];
    signal partial_sums[n+1];
    partial_sums[0] <== 0;
    
    for (var i = 0; i < n; i++) {
        multipliers[i] = Num2Bits(64);
        multipliers[i].in <== values[i] * weights[i];
        partial_sums[i+1] <== partial_sums[i] + values[i] * weights[i];
    }
    
    sum <== partial_sums[n];
}

// Template for sigmoid function approximation for response time scoring
template SigmoidApprox() {
    signal input response_time;
    signal input threshold;
    signal input alpha; // Steepness parameter
    signal output score;
    
    // Simplified sigmoid approximation: 1 / (1 + exp(alpha * (x - threshold)))
    // For circuit efficiency, we use a piecewise linear approximation
    
    signal diff <== response_time - threshold;
    signal scaled_diff <== diff * alpha;
    
    // Piecewise linear approximation of sigmoid
    // If diff <= -2: score = 1000 (scaled by 1000)
    // If -2 < diff < 2: score = 500 + (-250 * diff)  
    // If diff >= 2: score = 0
    
    component lt1 = LessThanEq(32);
    lt1.in[0] <== scaled_diff + 2000; // Adding offset for positive comparison
    lt1.in[1] <== 0;
    
    component lt2 = LessThanEq(32);
    lt2.in[0] <== 2000;
    lt2.in[1] <== scaled_diff + 2000;
    
    // Linear interpolation in middle region
    signal middle_score <== 500000 - (250 * scaled_diff); // Scaled by 1000
    
    // Select appropriate score based on ranges
    score <== lt1.out * 1000000 + (1 - lt1.out) * (1 - lt2.out) * 0 + (1 - lt1.out) * lt2.out * middle_score;
}

// Main reputation verification circuit
template AIAgentReputationVerifier() {
    // Private inputs (agent's actual performance data)
    signal input tasks_completed;
    signal input total_tasks_assigned;
    signal input correct_outputs;
    signal input total_outputs;
    signal input operational_time;
    signal input total_time;
    signal input total_review_score;
    signal input total_review_weight;
    signal input avg_response_time;
    
    // Public inputs (verification parameters)
    signal input min_reputation_threshold; // Minimum reputation required
    signal input response_time_threshold;
    signal input alpha_param; // Sigmoid steepness
    
    // Weights for different metrics (scaled by 1000)
    signal input weight_task_completion;    // Default: 250 (25%)
    signal input weight_accuracy;           // Default: 250 (25%)
    signal input weight_uptime;            // Default: 200 (20%)
    signal input weight_reviews;           // Default: 200 (20%)
    signal input weight_response_time;     // Default: 100 (10%)
    
    // Output
    signal output reputation_verified; // 1 if reputation >= threshold, 0 otherwise
    
    // Internal signals for metric calculations
    signal task_completion_rate;
    signal accuracy_score;
    signal uptime_ratio;
    signal user_review_score;
    signal response_time_score;
    signal final_reputation;
    
    // === CONSTRAINT 1: Task Completion Rate Calculation ===
    component task_div = SafeDivision(16);
    task_div.numerator <== tasks_completed;
    task_div.denominator <== total_tasks_assigned;
    task_completion_rate <== task_div.quotient;
    
    // Range check: 0 <= task_completion_rate <= 1 (scaled)
    component task_range = RangeCheck(32);
    task_range.value <== task_completion_rate;
    task_range.max_value <== 65536; // 2^16 for scaling factor
    task_range.valid === 1;
    
    // === CONSTRAINT 2: Accuracy Score Calculation ===
    component accuracy_div = SafeDivision(16);
    accuracy_div.numerator <== correct_outputs;
    accuracy_div.denominator <== total_outputs;
    accuracy_score <== accuracy_div.quotient;
    
    // Range check for accuracy
    component accuracy_range = RangeCheck(32);
    accuracy_range.value <== accuracy_score;
    accuracy_range.max_value <== 65536;
    accuracy_range.valid === 1;
    
    // === CONSTRAINT 3: Uptime Ratio Calculation ===
    component uptime_div = SafeDivision(16);
    uptime_div.numerator <== operational_time;
    uptime_div.denominator <== total_time;
    uptime_ratio <== uptime_div.quotient;
    
    // Range check for uptime
    component uptime_range = RangeCheck(32);
    uptime_range.value <== uptime_ratio;
    uptime_range.max_value <== 65536;
    uptime_range.valid === 1;
    
    // === CONSTRAINT 4: User Review Score Calculation ===
    component review_div = SafeDivision(16);
    review_div.numerator <== total_review_score;
    review_div.denominator <== total_review_weight;
    user_review_score <== review_div.quotient;
    
    // Range check for reviews
    component review_range = RangeCheck(32);
    review_range.value <== user_review_score;
    review_range.max_value <== 65536;
    review_range.valid === 1;
    
    // === CONSTRAINT 5: Response Time Score Calculation ===
    component sigmoid = SigmoidApprox();
    sigmoid.response_time <== avg_response_time;
    sigmoid.threshold <== response_time_threshold;
    sigmoid.alpha <== alpha_param;
    response_time_score <== sigmoid.score;
    
    // === CONSTRAINT 6: Weight Validation ===
    // Ensure weights sum to 1000 (representing 100% with scaling)
    signal weight_sum <== weight_task_completion + weight_accuracy + weight_uptime + weight_reviews + weight_response_time;
    weight_sum === 1000;
    
    // === CONSTRAINT 7: Final Reputation Calculation ===
    component weighted_calc = WeightedSum(5);
    weighted_calc.values[0] <== task_completion_rate;
    weighted_calc.values[1] <== accuracy_score;
    weighted_calc.values[2] <== uptime_ratio;
    weighted_calc.values[3] <== user_review_score;
    weighted_calc.values[4] <== response_time_score;
    
    weighted_calc.weights[0] <== weight_task_completion;
    weighted_calc.weights[1] <== weight_accuracy;
    weighted_calc.weights[2] <== weight_uptime;
    weighted_calc.weights[3] <== weight_reviews;
    weighted_calc.weights[4] <== weight_response_time;
    
    // Scale down the final result
    component final_div = SafeDivision(10);
    final_div.numerator <== weighted_calc.sum;
    final_div.denominator <== 1000;
    final_reputation <== final_div.quotient;
    
    // === CONSTRAINT 8: Threshold Verification ===
    component threshold_check = GreaterEqualThan(32);
    threshold_check.in[0] <== final_reputation;
    threshold_check.in[1] <== min_reputation_threshold;
    reputation_verified <== threshold_check.out;
    
    // === CONSTRAINT 9: Logical Consistency Checks ===
    // Tasks completed cannot exceed total tasks assigned
    component task_consistency = LessThanEq(32);
    task_consistency.in[0] <== tasks_completed;
    task_consistency.in[1] <== total_tasks_assigned;
    task_consistency.out === 1;
    
    // Correct outputs cannot exceed total outputs
    component output_consistency = LessThanEq(32);
    output_consistency.in[0] <== correct_outputs;
    output_consistency.in[1] <== total_outputs;
    output_consistency.out === 1;
    
    // Operational time cannot exceed total time
    component time_consistency = LessThanEq(32);
    time_consistency.in[0] <== operational_time;
    time_consistency.in[1] <== total_time;
    time_consistency.out === 1;
    
    // === CONSTRAINT 10: Non-zero Denominators ===
    // Ensure all denominators are positive
    component zero_check1 = IsZero();
    zero_check1.in <== total_tasks_assigned;
    zero_check1.out === 0;
    
    component zero_check2 = IsZero();
    zero_check2.in <== total_outputs;
    zero_check2.out === 0;
    
    component zero_check3 = IsZero();
    zero_check3.in <== total_time;
    zero_check3.out === 0;
    
    component zero_check4 = IsZero();
    zero_check4.in <== total_review_weight;
    zero_check4.out === 0;
}

// Component instantiation
component main = AIAgentReputationVerifier();