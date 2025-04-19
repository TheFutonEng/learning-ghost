package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"text/template"
)

// K3dCluster represents a k3d cluster from CLI output
type K3dCluster struct {
	Name  string `json:"name"`
	Ports []struct {
		Mappings []struct {
			PortOnHost string `json:"port_on_host"`
		} `json:"mappings"`
	} `json:"ports"`
}

// Config represents the template parameters
type Config struct {
	ClusterName       string
	K3dServers        int
	K3dAgents         int
	ApiServerPort     int
	ExternalHttpPort  int
	ExternalHttpsPort int
	ServersMemory     string
	ServersCPU        string
}

func main() {
	// Define command line flags
	clusterName := flag.String("name", "", "Name of the cluster (required)")
	k3dServers := flag.Int("servers", 1, "Number of K3d servers")
	k3dAgents := flag.Int("agents", 0, "Number of K3d agents")
	serversMemory := flag.String("memory", "1gb", "Memory for servers")
	serversCPU := flag.String("cpu", "1", "CPU allocation for servers")
	templatePath := flag.String("template", "k3d/k3d-template.yaml", "Path to the template file")
	outputPath := flag.String("output", "", "Output file path (defaults to k3d-config.yaml)")
	debug := flag.Bool("debug", false, "Enable debug output")

	flag.Parse()

	// Validate required params
	if *clusterName == "" {
		fmt.Println("Error: Cluster name is required. Use -name to specify a cluster name.")
		flag.Usage()
		os.Exit(1)
	}

	// Set default output path if not provided
	if *outputPath == "" {
		*outputPath = fmt.Sprintf("k3d/k3d-config.yaml")
	}

	// Find available ports
	apiPort, httpPort, httpsPort, err := findAvailablePorts(*debug)
	if err != nil {
		fmt.Printf("Error finding available ports: %v\n", err)
		os.Exit(1)
	}

	// Create config with all parameters
	config := Config{
		ClusterName:       *clusterName,
		K3dServers:        *k3dServers,
		K3dAgents:         *k3dAgents,
		ApiServerPort:     apiPort,
		ExternalHttpPort:  httpPort,
		ExternalHttpsPort: httpsPort,
		ServersMemory:     *serversMemory,
		ServersCPU:        *serversCPU,
	}

	// Process the template
	err = processTemplate(*templatePath, *outputPath, config)
	if err != nil {
		fmt.Printf("Error processing template: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Created K3d configuration file: %s\n", *outputPath)
	fmt.Printf("API Port: %d\n", apiPort)
	fmt.Printf("HTTP Port: %d\n", httpPort)
	fmt.Printf("HTTPS Port: %d\n", httpsPort)
}

// processTemplate reads the template file and writes the processed output
func processTemplate(templatePath, outputPath string, config Config) error {
	// Read template file
	tmplContent, err := os.ReadFile(templatePath)
	if err != nil {
		return fmt.Errorf("failed to read template file: %w", err)
	}

	// Create template from string
	tmpl, err := template.New("k3d").Parse(string(tmplContent))
	if err != nil {
		return fmt.Errorf("failed to parse template: %w", err)
	}

	// Create output file
	outFile, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("failed to create output file: %w", err)
	}
	defer outFile.Close()

	// Execute template
	err = tmpl.Execute(outFile, config)
	if err != nil {
		return fmt.Errorf("failed to execute template: %w", err)
	}

	return nil
}

// findAvailablePorts finds the next available ports for API, HTTP, and HTTPS
func findAvailablePorts(debug bool) (int, int, int, error) {
	// Start with default ports
	apiPort := 6443
	httpPort := 8080
	httpsPort := 8443

	// Get all used ports from both k3d and docker
	usedPorts := make(map[int]bool)

	// Method 1: Check k3d clusters
	clusters, err := getK3dClusters()
	if err != nil {
		// Log the error but continue - we'll still check Docker
		fmt.Printf("Warning: Couldn't get k3d clusters: %v\n", err)
	} else {
		for _, cluster := range clusters {
			for _, portData := range cluster.Ports {
				for _, mapping := range portData.Mappings {
					if port, err := strconv.Atoi(mapping.PortOnHost); err == nil {
						usedPorts[port] = true
					}
				}
			}
		}
	}

	// Method 2: Check docker directly for more reliable port information
	cmd := exec.Command("docker", "ps", "--format", "{{.Ports}}")
	output, err := cmd.CombinedOutput()
	if err == nil {
		// Parse docker output for port mappings
		portLines := strings.Split(string(output), "\n")
		for _, line := range portLines {
			if line == "" {
				continue
			}

			// Docker format is like: 0.0.0.0:8080->80/tcp, [::]:8080->80/tcp, ...
			portMappings := strings.Split(line, ", ")
			for _, mapping := range portMappings {
				// Find patterns like 0.0.0.0:8080->80/tcp or [::]:8080->80/tcp
				re := regexp.MustCompile(`[0-9.]+:(\d+)->|::]:(\d+)->`)
				matches := re.FindStringSubmatch(mapping)
				if len(matches) > 1 {
					portStr := matches[1]
					if portStr == "" {
						portStr = matches[2]
					}
					if port, err := strconv.Atoi(portStr); err == nil {
						usedPorts[port] = true
					}
				}
			}
		}
	} else {
		fmt.Printf("Warning: Couldn't get Docker port information: %v\n", err)
	}

	// Find next available ports
	for usedPorts[apiPort] {
		apiPort++
	}

	for usedPorts[httpPort] {
		httpPort++
	}

	for usedPorts[httpsPort] {
		httpsPort++
	}

	if debug {
		fmt.Println("--- Debug Port Information ---")
		fmt.Println("Used ports detected:")
		for port := range usedPorts {
			fmt.Printf("  %d\n", port)
		}
		fmt.Println("Selected ports:")
		fmt.Printf("  API: %d\n", apiPort)
		fmt.Printf("  HTTP: %d\n", httpPort)
		fmt.Printf("  HTTPS: %d\n", httpsPort)
		fmt.Println("----------------------------")
	}

	return apiPort, httpPort, httpsPort, nil
}

// getK3dClusters executes k3d cluster list and returns parsed results
func getK3dClusters() ([]K3dCluster, error) {
	cmd := exec.Command("k3d", "cluster", "list", "-o", "json")
	output, err := cmd.CombinedOutput()
	if err != nil {
		// If there are no clusters, k3d might return an error
		// Check if the error is "No clusters found" and return empty list
		if strings.Contains(string(output), "No clusters found") {
			return []K3dCluster{}, nil
		}
		return nil, fmt.Errorf("failed to list k3d clusters: %w, output: %s", err, output)
	}

	var clusters []K3dCluster
	err = json.Unmarshal(output, &clusters)
	if err != nil {
		return nil, fmt.Errorf("failed to parse k3d cluster list: %w", err)
	}

	return clusters, nil
}
