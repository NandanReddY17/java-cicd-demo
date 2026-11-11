package com.example.cicddemo;

import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** App info shown in the page header/footer and used by the pipeline to verify the deployed build. */
@RestController
public class HomeController {

    /** Git commit SHA of the running image, injected by Kubernetes (APP_BUILD env var). */
    @Value("${app.build:local}")
    private String build;

    /** Pod name; shows which replica answered the request. */
    @Value("${HOSTNAME:localhost}")
    private String servedBy;

    @GetMapping("/api/info")
    public Map<String, String> info() {
        Map<String, String> body = new LinkedHashMap<>();
        body.put("message", "Simple Calculator v4 - auto-deployed to Azure AKS");
        body.put("version", "1.0.0");
        body.put("build", build);
        body.put("servedBy", servedBy);
        return body;
    }
}
