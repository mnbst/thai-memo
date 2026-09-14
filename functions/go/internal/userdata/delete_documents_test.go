package userdata

import (
	"context"
	"net"
	"strings"
	"testing"

	"cloud.google.com/go/firestore"
	pb "cloud.google.com/go/firestore/apiv1/firestorepb"
	"google.golang.org/api/option"
	rpcstatus "google.golang.org/genproto/googleapis/rpc/status"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type deleteServer struct {
	pb.UnimplementedFirestoreServer
	rpcFailure bool
}

func (s *deleteServer) BatchWrite(_ context.Context, req *pb.BatchWriteRequest) (*pb.BatchWriteResponse, error) {
	if s.rpcFailure {
		return nil, status.Error(codes.PermissionDenied, "injected transport failure")
	}
	resp := &pb.BatchWriteResponse{}
	for _, write := range req.Writes {
		result := &rpcstatus.Status{}
		if strings.HasSuffix(write.GetDelete(), "/fail") {
			result = &rpcstatus.Status{Code: int32(codes.PermissionDenied), Message: "injected write failure"}
		}
		resp.Status = append(resp.Status, result)
		resp.WriteResults = append(resp.WriteResults, &pb.WriteResult{UpdateTime: timestamppb.Now()})
	}
	return resp, nil
}

func TestDeleteDocumentsChecksServerResults(t *testing.T) {
	for _, test := range []struct {
		name       string
		id         string
		rpcFailure bool
		wantError  bool
	}{
		{"success", "ok", false, false},
		{"individual write fails", "fail", false, true},
		{"RPC fails", "ok", true, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			listener := bufconn.Listen(1024 * 1024)
			server := grpc.NewServer()
			pb.RegisterFirestoreServer(server, &deleteServer{rpcFailure: test.rpcFailure})
			go func() { _ = server.Serve(listener) }()
			t.Cleanup(server.Stop)
			t.Cleanup(func() { _ = listener.Close() })
			conn, err := grpc.NewClient("passthrough:///firestore-test",
				grpc.WithTransportCredentials(insecure.NewCredentials()),
				grpc.WithContextDialer(func(context.Context, string) (net.Conn, error) { return listener.Dial() }))
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = conn.Close() })
			db, err := firestore.NewClient(context.Background(), "test", option.WithGRPCConn(conn))
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = db.Close() })
			err = DeleteDocuments(context.Background(), db, []*firestore.DocumentRef{
				db.Collection("records").Doc("first"), db.Collection("records").Doc(test.id),
			})
			if (err != nil) != test.wantError {
				t.Fatalf("DeleteDocuments error = %v, wantError = %v", err, test.wantError)
			}
		})
	}
}
