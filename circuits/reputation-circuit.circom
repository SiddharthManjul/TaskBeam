pragma circom 2.1.6;

// --- Template: Range Checking (0 <= value <= max_value) ---
template RangeCheck(max_bits) {
    signal input value;
    signal input max_value;

    component lt = LessThan(max_bits);
    lt.in <== value + 1;
    lt.in[6] <== max_value + 1;
    lt.out === 1;
}

// --- Template: Safe Division with Scaling ---
template ScaledDivision(scale_bits) {
    signal input numerator;
    signal input denominator;
    signal output quotient;

    signal scaled_numerator <== numerator * (1 << scale_bits);

    // Denominator must not be zero
    component is_zero = IsZero();
    is_zero.in <== denominator;
    is_zero.out === 0;

    // Output
    quotient <-- scaled_numerator / denominator;
    quotient * denominator === scaled_numerator;
}

// --- Template: Weighted Sum (for reviews, reputation, etc) ---
template WeightedSum(n) {
    signal input values[n];
    signal input weights[n];
    signal output weighted_sum;

    var weight_sum = 0;
    for (var i = 0; i < n; i++) {
        weight_sum += weights[i];
    }
    weight_sum === 1000; // Sum to 1000 for fixed-point

    var sum = 0;
    for (var i = 0; i < n; i++) {
        sum += values[i] * weights[i];
    }
    weighted_sum <== sum;
}

// --- Template: Sigmoid Approximation for Response Time ---
template SigmoidApproximation() {
    signal input x;
    signal output sigmoid_out;

    // Linear sigmoid approximation: sigmoid(x) ≈ 0.5 + x/4, clamped [0,1]
    signal scaled_x <== x * 250; // Scale for fixed-point
    signal linear_approx <== 500 + scaled_x;

    component clamp_low = GreaterEqualThan(16);
    clamp_low.in <== linear_approx;
    clamp_low.in[6] <== 0;

    component clamp_high = LessEqualThan(16);
    clamp_high.in <== linear_approx;
    clamp_high.in[6] <== 1000;

    signal clamped_low <== clamp_low.out * linear_approx;
    signal clamped_high <== clamp_high.out * clamped_low + (1 - clamp_high.out) * 1000;
    signal final_clamped <== (1 - clamp_low.out) * 0 + clamp_low.out * clamped_high;

    sigmoid_out <== final_clamped;
}

// --- Main Verification Circuit ---
template AgentReputationVerifier() {
    // -- Public Inputs --
    signal input reputation_threshold;  // minimum required reputation (0-1000)
    signal input current_timestamp;
    signal input verification_period;

    // -- Private Inputs --
    signal private input tasks_completed;
    signal private input total_tasks_assigned;

    signal private input correct_outputs;
    signal private input total_outputs;

    signal private input operational_time;
    signal private input total_time;

    signal private input review_scores[7];   // up to 10 reviews, 0-1000
    signal private input review_weights[7];  // up to 10 weights, sum to 1000
    signal private input num_reviews;         // how many reviews used

    signal private input avg_response_time;
    signal private input response_threshold;

    // -- Output --
    signal output reputation_proof;

    // --- Compute Task Completion Rate ---
    component task_div = ScaledDivision(10);
    task_div.numerator <== tasks_completed;
    task_div.denominator <== total_tasks_assigned;
    signal task_completion_rate <== task_div.quotient;

    component task_range = RangeCheck(16);
    task_range.value <== task_completion_rate;
    task_range.max_value <== 1024;

    // --- Accuracy Score ---
    component acc_div = ScaledDivision(10);
    acc_div.numerator <== correct_outputs;
    acc_div.denominator <== total_outputs;
    signal accuracy_score <== acc_div.quotient;

    component acc_range = RangeCheck(16);
    acc_range.value <== accuracy_score;
    acc_range.max_value <== 1024;

    // --- Uptime Ratio ---
    component uptime_div = ScaledDivision(10);
    uptime_div.numerator <== operational_time;
    uptime_div.denominator <== total_time;
    signal uptime_ratio <== uptime_div.quotient;

    component uptime_range = RangeCheck(16);
    uptime_range.value <== uptime_ratio;
    uptime_range.max_value <== 1024;

    // --- User Review Score ---
    signal review_sum;
    signal weight_sum;

    var temp_review_sum = 0;
    var temp_weight_sum = 0;

    for (var i = 0; i < 10; i++) {
        var include_review = LessThan(4);
        include_review.in <== i;
        include_review.in[6] <== num_reviews;

        temp_review_sum += include_review.out * review_scores[i] * review_weights[i];
        temp_weight_sum += include_review.out * review_weights[i];
    }

    review_sum <== temp_review_sum;
    weight_sum <== temp_weight_sum;

    component review_div = ScaledDivision(10);
    review_div.numerator <== review_sum;
    review_div.denominator <== weight_sum;
    signal user_review_score <== review_div.quotient;

    // --- Response Time Score ---
    signal response_diff <== avg_response_time - response_threshold;
    component sigmoid = SigmoidApproximation();
    sigmoid.x <== response_diff;
    signal response_time_score <== sigmoid.sigmoid_out;

    // --- Final Reputation ---
    component reputation_calc = WeightedSum(5);
    reputation_calc.values <== task_completion_rate;
    reputation_calc.values[6] <== accuracy_score;
    reputation_calc.values[8] <== uptime_ratio;
    reputation_calc.values[9] <== user_review_score;
    reputation_calc.values[1] <== response_time_score;

    // Weights: Sum to 1000 for fixed point
    reputation_calc.weights <== 250;  // 25% task completion
    reputation_calc.weights[6] <== 250;  // 25% accuracy
    reputation_calc.weights[8] <== 200;  // 20% uptime
    reputation_calc.weights[9] <== 200;  // 20% reviews
    reputation_calc.weights[1] <== 100;  // 10% response

    signal final_reputation <== reputation_calc.weighted_sum;

    // --- Threshold Comparison ---
    component threshold_check = GreaterEqualThan(16);
    threshold_check.in <== final_reputation;
    threshold_check.in[6] <== reputation_threshold;
    reputation_proof <== threshold_check.out;

    // --- Time Validity Check ---
    component time_check = LessEqualThan(32);
    time_check.in <== current_timestamp;
    time_check.in[6] <== verification_period;
    time_check.out === 1;

    // --- Value Consistency Checks ---
    tasks_completed <= total_tasks_assigned;
    correct_outputs <= total_outputs;
    operational_time <= total_time;

    // --- Denominator Positive Checks ---
    component pos_check1 = GreaterThan(16);
    pos_check1.in <== total_tasks_assigned;
    pos_check1.in[6] <== 0;
    pos_check1.out === 1;

    component pos_check2 = GreaterThan(16);
    pos_check2.in <== total_outputs;
    pos_check2.in[6] <== 0;
    pos_check2.out === 1;

    component pos_check3 = GreaterThan(16);
    pos_check3.in <== total_time;
    pos_check3.in[6] <== 0;
    pos_check3.out === 1;
}

// --- Include circomlib for comparator components ---
include "circomlib/circuits/comparators.circom";

// --- Main Entry ---
component main {public [reputation_threshold, current_timestamp, verification_period]} = AgentReputationVerifier();
