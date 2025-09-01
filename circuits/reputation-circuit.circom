pragma circom 2.1.6;

// ========================================
// INCLUDE STATEMENTS MUST COME FIRST
// ========================================
include "circomlib/circuits/comparators.circom";

// ========================================
// TEMPLATE DEFINITIONS
// ========================================

// Template: Range Checking (0 <= value <= max_value)
template RangeCheck(max_bits) {
    signal input value;
    signal input max_value;

    component lt = LessThan(max_bits);
    lt.in[0] <== value + 1;
    lt.in[1] <== max_value + 1;
    lt.out === 1;
}

// Template: Safe Division with Scaling
template ScaledDivision(scale_bits) {
    signal input numerator;
    signal input denominator;
    signal output quotient;

    signal scaled_numerator <== numerator * (1 << scale_bits);

    // Denominator must not be zero
    component is_zero = IsZero();
    is_zero.in <== denominator;
    is_zero.out === 0;

    // Calculate quotient
    quotient <-- scaled_numerator / denominator;
    quotient * denominator === scaled_numerator;
}

// Template: Weighted Sum calculation
template WeightedSum(n) {
    signal input values[n];
    signal input weights[n];
    signal output weighted_sum;

    // Ensure weights sum to 1000 (representing 1.0)
    var weight_sum = 0;
    for (var i = 0; i < n; i++) {
        weight_sum += weights[i];
    }
    weight_sum === 1000;

    // Calculate weighted sum
    var sum = 0;
    for (var i = 0; i < n; i++) {
        sum += values[i] * weights[i];
    }
    weighted_sum <== sum;
}

// Template: Sigmoid Approximation for Response Time
template SigmoidApproximation() {
    signal input x;
    signal output sigmoid_out;

    // Linear sigmoid approximation: sigmoid(x) ≈ 0.5 + x/4, clamped [0,1]
    signal scaled_x <== x * 250; // Scale for fixed-point
    signal linear_approx <== 500 + scaled_x;

    component clamp_low = GreaterEqualThan(16);
    clamp_low.in[0] <== linear_approx;
    clamp_low.in[1] <== 0;

    component clamp_high = LessEqualThan(16);
    clamp_high.in[0] <== linear_approx;
    clamp_high.in[1] <== 1000;

    signal clamped_low <== clamp_low.out * linear_approx;
    signal clamped_high <== clamp_high.out * clamped_low + (1 - clamp_high.out) * 1000;
    signal final_clamped <== (1 - clamp_low.out) * 0 + clamp_low.out * clamped_high;

    sigmoid_out <== final_clamped;
}

// ========================================
// MAIN CIRCUIT TEMPLATE
// ========================================

template AgentReputationVerifier() {
    // Public inputs
    signal input reputation_threshold;  // minimum required reputation (0-1000)
    signal input current_timestamp;
    signal input verification_period;

    // Private inputs - Task completion metrics
    signal private input tasks_completed;
    signal private input total_tasks_assigned;

    // Private inputs - Accuracy metrics  
    signal private input correct_outputs;
    signal private input total_outputs;

    // Private inputs - Uptime metrics
    signal private input operational_time;
    signal private input total_time;

    // Private inputs - User review metrics
    signal private input review_scores[10];   // up to 10 reviews, 0-1000
    signal private input review_weights[10];  // up to 10 weights
    signal private input num_reviews;         // actual number of reviews

    // Private inputs - Response time metrics
    signal private input avg_response_time;
    signal private input response_threshold;

    // Output
    signal output reputation_proof;

    // ========================================
    // METRIC CALCULATIONS
    // ========================================

    // Task Completion Rate
    component task_div = ScaledDivision(10);
    task_div.numerator <== tasks_completed;
    task_div.denominator <== total_tasks_assigned;
    signal task_completion_rate <== task_div.quotient;

    component task_range = RangeCheck(16);
    task_range.value <== task_completion_rate;
    task_range.max_value <== 1024;

    // Accuracy Score
    component acc_div = ScaledDivision(10);
    acc_div.numerator <== correct_outputs;
    acc_div.denominator <== total_outputs;
    signal accuracy_score <== acc_div.quotient;

    component acc_range = RangeCheck(16);
    acc_range.value <== accuracy_score;
    acc_range.max_value <== 1024;

    // Uptime Ratio
    component uptime_div = ScaledDivision(10);
    uptime_div.numerator <== operational_time;
    uptime_div.denominator <== total_time;
    signal uptime_ratio <== uptime_div.quotient;

    component uptime_range = RangeCheck(16);
    uptime_range.value <== uptime_ratio;
    uptime_range.max_value <== 1024;

    // User Review Score (weighted average)
    signal review_sum;
    signal weight_sum;

    var temp_review_sum = 0;
    var temp_weight_sum = 0;

    for (var i = 0; i < 10; i++) {
        // Use ternary-like logic to include only valid reviews
        component include_check = LessThan(4);
        include_check.in[0] <== i;
        include_check.in[1] <== num_reviews;

        temp_review_sum += include_check.out * review_scores[i] * review_weights[i];
        temp_weight_sum += include_check.out * review_weights[i];
    }

    review_sum <== temp_review_sum;
    weight_sum <== temp_weight_sum;

    component review_div = ScaledDivision(10);
    review_div.numerator <== review_sum;
    review_div.denominator <== weight_sum;
    signal user_review_score <== review_div.quotient;

    // Response Time Score
    signal response_diff <== avg_response_time - response_threshold;
    component sigmoid = SigmoidApproximation();
    sigmoid.x <== response_diff;
    signal response_time_score <== sigmoid.sigmoid_out;

    // ========================================
    // FINAL REPUTATION CALCULATION
    // ========================================

    component reputation_calc = WeightedSum(5);
    reputation_calc.values[0] <== task_completion_rate;
    reputation_calc.values[1] <== accuracy_score;
    reputation_calc.values[2] <== uptime_ratio;
    reputation_calc.values[3] <== user_review_score;
    reputation_calc.values[4] <== response_time_score;

    // Weights (sum to 1000 for fixed-point arithmetic)
    reputation_calc.weights[0] <== 250;  // 25% task completion
    reputation_calc.weights[1] <== 250;  // 25% accuracy
    reputation_calc.weights[2] <== 200;  // 20% uptime
    reputation_calc.weights[3] <== 200;  // 20% user reviews
    reputation_calc.weights[4] <== 100;  // 10% response time

    signal final_reputation <== reputation_calc.weighted_sum;

    // ========================================
    // VERIFICATION AND CONSTRAINTS
    // ========================================

    // Threshold comparison
    component threshold_check = GreaterEqualThan(16);
    threshold_check.in[0] <== final_reputation;
    threshold_check.in[1] <== reputation_threshold;
    reputation_proof <== threshold_check.out;

    // Time validity check
    component time_check = LessEqualThan(32);
    time_check.in[0] <== current_timestamp;
    time_check.in[1] <== verification_period;
    time_check.out === 1;

    // Logic consistency constraints
    tasks_completed <= total_tasks_assigned;
    correct_outputs <= total_outputs;
    operational_time <= total_time;

    // Ensure positive denominators
    component pos_check1 = GreaterThan(16);
    pos_check1.in[0] <== total_tasks_assigned;
    pos_check1.in[1] <== 0;
    pos_check1.out === 1;

    component pos_check2 = GreaterThan(16);
    pos_check2.in[0] <== total_outputs;
    pos_check2.in[1] <== 0;
    pos_check2.out === 1;

    component pos_check3 = GreaterThan(16);
    pos_check3.in[0] <== total_time;
    pos_check3.in[1] <== 0;
    pos_check3.out === 1;
}

// ========================================
// MAIN COMPONENT INSTANTIATION
// ========================================

component main {public [reputation_threshold, current_timestamp, verification_period]} = AgentReputationVerifier();
