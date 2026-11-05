package com.example.cicddemo;

import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

/**
 * REST API for the calculator.
 * Example: GET /api/calculate?a=8&b=2&op=divide  ->  {"a":8.0,"b":2.0,"op":"divide","result":4.0}
 */
@RestController
public class CalculatorController {

    private final CalculatorService calculatorService;

    public CalculatorController(CalculatorService calculatorService) {
        this.calculatorService = calculatorService;
    }

    @GetMapping("/api/calculate")
    public Map<String, Object> calculate(@RequestParam double a,
                                         @RequestParam double b,
                                         @RequestParam String op) {
        double result = calculatorService.calculate(a, b, op);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("a", a);
        body.put("b", b);
        body.put("op", op);
        body.put("result", result);
        return body;
    }

    /** Divide by zero, unknown operation -> 400 Bad Request with a readable message. */
    @ExceptionHandler(IllegalArgumentException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Map<String, String> handleBadInput(IllegalArgumentException ex) {
        return Map.of("error", ex.getMessage());
    }

    /** Missing parameter or a non-number like a=abc -> 400 Bad Request. */
    @ExceptionHandler({MissingServletRequestParameterException.class, MethodArgumentTypeMismatchException.class})
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Map<String, String> handleBadRequest(Exception ex) {
        return Map.of("error", "Please provide numbers a and b and an operation op");
    }
}
